// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Render queue and history (ArchiApp/RenderQueue.swift RenderQueue / RenderQueueWindow / RenderQueueView, VIS-076 /
// VIS-079): jobs from the current view, saved cameras or camera path keys, a preset and a size, rendered in turn to
// PNG files in the output folder (Pictures\Archi Renders by default), with the last 50 renders as thumbnails.
import type { App } from "../app";
import { h, clear } from "../dom";
import { toolWindow, picker, flatButton, note, label, row, Option } from "../dialogs/ui";
import { sym as icon } from "./icons";
import { renderImage, defaultSettings, applyPreset, ModelCamera, OutputPreset } from "./render";
import { view3d, modelCamera, renderWindowInfo } from "./context";
import { writeBytes, encodePixels, out, docName, dataURL, fileName } from "./native";

type Status = { kind: "pending" } | { kind: "running" } | { kind: "done"; path: string } | { kind: "failed"; message: string };
export interface Job { id: number; name: string; camera: ModelCamera | null; preset: string | null; width: number; height: number; status: Status; seconds: number }
interface HistoryItem { path: string; name: string; date: number; seconds: number; thumb?: string }

const HISTORY_KEY = "archi.render.history", FOLDER_KEY = "archi.render.queueFolder";
let nextId = 1;
export const queue = {
  jobs: [] as Job[],
  running: false,
  cancelRequested: false,
  history: load<HistoryItem[]>(HISTORY_KEY, []),
  listeners: new Set<() => void>(),
  changed() { this.listeners.forEach((l) => l()); },
  add(name: string, camera: ModelCamera | null, preset: string | null, width = 1920, height = 1080) {
    this.jobs.push({ id: nextId++, name, camera, preset, width, height, status: { kind: "pending" }, seconds: 0 });
    this.changed();
  },
  get pendingCount() { return this.jobs.filter((j) => j.status.kind === "pending").length; },
  clearFinished() { this.jobs = this.jobs.filter((j) => j.status.kind === "pending" || j.status.kind === "running"); this.changed(); },
};
(window as any).archiRenderQueue = queue;
function load<T>(k: string, d: T): T { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch { return d; } }
function save(k: string, v: unknown) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* quota */ } }

export async function outputFolder(): Promise<string> {
  const f = load<string | null>(FOLDER_KEY, null);
  if (f) return f;
  const n = out();
  const pics = n ? (await n.folders()).pictures : "Pictures";
  return `${pics}\\Archi Renders`;
}

/** Renders the pending jobs one after the other (RenderQueue.start). */
export async function runQueue(app: App) {
  if (queue.running) return;
  queue.running = true; queue.cancelRequested = false; queue.changed();
  const folder = await outputFolder();
  const info = await renderWindowInfo(app);
  const presets: OutputPreset[] = info.presets ?? [];
  const site = { latitude: info.latitude, longitude: info.longitude, northAngle: info.northAngle };
  let v;
  try { v = await view3d(); } catch (e: any) { app.print(String(e?.message ?? e)); queue.running = false; queue.changed(); return; }
  while (!queue.cancelRequested) {
    const job = queue.jobs.find((j) => j.status.kind === "pending");
    if (!job) break;
    job.status = { kind: "running" }; queue.changed();
    const s = defaultSettings();
    const p = presets.find((x) => x.name === job.preset);
    if (p) applyPreset(p, s);
    s.width = job.width; s.height = job.height;
    const t0 = performance.now();
    try {
      const px = await renderImage(v, { settings: s, site, camera: job.camera ?? modelCamera(v), verticalCorrection: false });
      job.seconds = (performance.now() - t0) / 1000;
      const names = new Set(((await out()?.list(folder)) ?? []).map((x) => x.toLowerCase()));
      const r = await app.tryCall("render.queueName", { name: job.name });
      let file: string = r?.file ?? `${job.name}.png`;
      for (let k = 2; names.has(file.toLowerCase()); k++) file = file.replace(/( \d+)?\.png$/i, ` ${k}.png`);
      const path = `${folder}\\${file}`;
      await writeBytes(path, await encodePixels(px));
      job.status = { kind: "done", path };
      const thumb = dataURL(shrink(px, 240));
      queue.history.unshift({ path, name: job.name, date: Date.now(), seconds: job.seconds, thumb });
      if (queue.history.length > 50) queue.history.length = 50;
      save(HISTORY_KEY, queue.history);
    } catch (e: any) { job.status = { kind: "failed", message: String(e?.message ?? "Rendering failed") }; }
    queue.changed();
  }
  queue.running = false; queue.changed();
  app.print(`Render queue finished: ${queue.jobs.filter((j) => j.status.kind === "done").length} image(s) in ${folder}.`);
}

function shrink(px: { width: number; height: number; data: Uint8Array }, w: number) {
  const k = Math.max(1, Math.ceil(px.width / w));
  const ow = Math.max(1, Math.floor(px.width / k)), oh = Math.max(1, Math.floor(px.height / k));
  const d = new Uint8Array(ow * oh * 4);
  for (let y = 0; y < oh; y++) for (let x = 0; x < ow; x++) { const s = ((y * k) * px.width + x * k) * 4; d.set(px.data.subarray(s, s + 4), (y * ow + x) * 4); }
  return { width: ow, height: oh, data: d };
}

let listener: (() => void) | null = null;
export async function openRenderQueue(app: App, add: { name: string; camera: ModelCamera | null; numbered?: boolean }[] = [], run = false) {
  const info = await renderWindowInfo(app);
  let preset = "", size = "1920×1080";
  const sizes = ["1280×720", "1920×1080", "2560×1440", "3840×2160", "2048×2048"];
  const wh = () => size.split("×").map(Number);
  for (const a of add) {
    const name = a.numbered ? `${a.name} ${queue.jobs.length + 1}` : a.name;
    let cam = a.camera;
    if (!cam) { try { cam = modelCamera(await view3d()); } catch { cam = null; } }
    queue.add(name, cam, null);
  }
  toolWindow("renderQueue", "Render Queue", 520, 560, (body) => {
    const col = h("div", { class: "dcol rq" });
    body.append(col);
    const render = async () => {
      clear(col);
      const folder = await outputFolder();
      col.append(row(picker([{ value: "", title: "Default" }, ...(info.presets as OutputPreset[]).map((p) => ({ value: p.name, title: p.name }))], preset, (v) => { preset = v; }, { label: "Preset", width: 150 }),
        picker(sizes.map((s) => ({ value: s, title: s } as Option)), size, (v) => { size = v; }, { label: "Size", width: 100 })));
      col.append(row(
        flatButton("Add Current View", async () => { const v = await view3d().catch(() => null); const [w, hh] = wh(); queue.add(`${docName(app)} – view ${queue.jobs.length + 1}`, v ? modelCamera(v) : null, preset || null, w, hh); }, { compact: true }),
        flatButton("Add Saved Cameras", () => { const [w, hh] = wh(); for (const c of info.cameras as ModelCamera[]) queue.add(`${docName(app)} – ${c.name}`, c, preset || null, w, hh); }, { compact: true, disabled: !(info.cameras ?? []).length }),
        h("span", { class: "spacer" }),
        flatButton("Folder…", async () => { const n = app.engine.native; const p = n?.chooseFolder ? await n.chooseFolder({ title: "Choose the folder for queued renders", defaultPath: folder }) : null; if (p) { save(FOLDER_KEY, p); void render(); } }, { compact: true, help: folder })));
      const list = h("div", { class: "dlist rq-list" });
      for (const j of queue.jobs) {
        const st = j.status;
        const ic = st.kind === "pending" ? icon("clock", 12) : st.kind === "running" ? icon("hourglass", 12) : st.kind === "done" ? icon("checkmark.circle.fill", 12) : icon("exclamationmark.triangle.fill", 12);
        (ic as any).classList?.add(`rq-${st.kind}`);
        const extra = st.kind === "failed" ? ` · ${st.message}` : st.kind === "done" ? ` · ${fileName(st.path)}` : "";
        const sub = `${j.width}×${j.height}${j.preset ? " · " + j.preset : ""}${j.seconds > 0 ? ` · ${j.seconds.toFixed(1)} s` : ""}${extra}`;
        const rm = st.kind === "pending" ? flatButton("✕", () => { queue.jobs = queue.jobs.filter((x) => x.id !== j.id); queue.changed(); }, { compact: true }) : null;
        list.append(h("div", { class: "li rq-job" }, ic, h("div", { class: "dcol", style: { gap: "1px" } }, h("span", { text: j.name }), h("span", { class: "s", text: sub })), h("span", { class: "spacer" }), rm));
      }
      col.append(list);
      col.append(row(
        flatButton(queue.running ? "Stop After Current" : `Render ${queue.pendingCount} Job(s)`, () => { if (queue.running) queue.cancelRequested = true; else void runQueue(app); }, { disabled: !queue.running && queue.pendingCount === 0 }),
        flatButton("Clear Finished", () => queue.clearFinished(), { compact: true }), h("span", { class: "spacer" }), note(fileName(folder))));
      col.append(h("div", { class: "hsep" }), label("Render history", { bold: true }));
      const hist = h("div", { class: "rq-history" });
      for (const it of queue.history) {
        const th = h("div", { class: "rq-thumb", title: it.path }, it.thumb ? h("img", { src: it.thumb, alt: "" }) : icon("photo", 16));
        const cell = h("div", { class: "rq-item" }, th, h("div", { class: "rq-n", text: it.name }), h("div", { class: "rq-d", text: `${new Date(it.date).toLocaleString([], { dateStyle: "short", timeStyle: "short" })} · ${it.seconds.toFixed(1)} s` }));
        cell.addEventListener("dblclick", () => void out()?.openPath(it.path));
        cell.addEventListener("contextmenu", (e) => {
          e.preventDefault();
          const m = h("div", { class: "menu" });
          Object.assign(m.style, { left: e.clientX + "px", top: e.clientY + "px" });
          const item = (t: string, f: () => void) => { const mi = h("div", { class: "mi", text: t }); mi.addEventListener("click", () => { m.remove(); f(); }); m.append(mi); };
          item("Open", () => void out()?.openPath(it.path));
          item("Show in Explorer", () => void out()?.reveal(it.path));
          item("Remove from History", () => { queue.history = queue.history.filter((x) => x !== it); save(HISTORY_KEY, queue.history); queue.changed(); });
          document.body.append(m);
          setTimeout(() => addEventListener("mousedown", function x(ev) { if (!m.contains(ev.target as Node)) { m.remove(); removeEventListener("mousedown", x); } }), 0);
        });
        hist.append(cell);
      }
      col.append(hist);
    };
    listener = () => void render();
    queue.listeners.add(listener);
    void render();
  }, () => { if (listener) queue.listeners.delete(listener); listener = null; /* the queue keeps running */ });
  if (run) void runQueue(app);
}
