// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The Path Tracer window (ArchiApp/PathTracerUI.swift PathTraceWindow / PathTraceView / PathTraceController): the
// engine's progressive path tracer (Host/EnginePathTracer.swift, VIS-070) seen from the 3D view's camera, samples per
// pixel, denoising (VIS-071), exposure and the light mix of the sun, sky and artificial light groups (VIS-078),
// changeable while and after rendering; Save… writes the tone-mapped PNG.
import type { App } from "../app";
import { h, clear } from "../dom";
import { toolWindow, picker, toggle, flatButton, label, row, stepper, slider, divider } from "../dialogs/ui";
import { modelCamera } from "./context";
import { saveDialog, sleep } from "./native";

export interface Mix { sun: number; sky: number; artificial: number }
export const tracer: { running: boolean; samples: number; image: string | null; mix: Mix; start?: () => Promise<void> } = { running: false, samples: 0, image: null, mix: { sun: 1, sky: 1, artificial: 1 } };

export async function openPathTrace(app: App, start = true) {
  const m = await app.tryCall("pathtrace.mix", {});
  if (m) tracer.mix = { sun: m.sun, sky: m.sky, artificial: m.artificial };
  let width = 960, height = 540, target = 64, denoise = true, ev = 0, status = "";
  let poll = 0;
  toolWindow("pathTrace", "Path Tracer", 1180, 640, (body, win) => {
    const stage = h("div", { class: "pt-stage" });
    const side = h("div", { class: "pt-side" });
    body.append(stage, h("div", { class: "vsep" }), side);
    const renderStage = () => {
      clear(stage);
      if (tracer.image) stage.append(h("img", { class: "pt-img", src: tracer.image, alt: "Path traced" }));
      else stage.append(h("span", { class: "rw-hint", text: "Press Render to path trace the 3D view" }));
    };
    const statusEl = h("div", { class: "dnote pt-status" });
    const renderSide = () => {
      clear(side);
      const mixRow = (t: string, k: keyof Mix) => {
        const v = label(tracer.mix[k].toFixed(2), { mono: true, width: 34 });
        return row(label(t, { width: 64 }), slider(0, 4, 0.01, tracer.mix[k], (x) => { tracer.mix[k] = x; v.textContent = x.toFixed(2); void refresh(); }, 100), v);
      };
      side.append(label("Path Tracer", { bold: true }),
        row(flatButton(tracer.running ? "Stop" : "Render", () => void (tracer.running ? stop() : begin()), { compact: true }), flatButton("Save…", () => void save(), { compact: true, disabled: !tracer.image })),
        picker(["640x360", "960x540", "1280x720", "1920x1080", "800x800"].map((s) => ({ value: s, title: s })), `${width}x${height}`, (v) => { const p = v.split("x").map(Number); width = p[0]; height = p[1]; }, { label: "Size", width: 110 }),
        stepper((v) => `Samples: ${v}`, target, 4, 4096, (v) => { target = v; }, { step: 16 }),
        toggle("Denoise", denoise, (v) => { denoise = v; void refresh(); }),
        row(label("Exposure"), slider(-3, 3, 0.1, ev, (v) => { ev = v; void refresh(); }, 130)),
        divider(), label("Light Mix", { bold: true }),
        mixRow("Sun", "sun"), mixRow("Sky", "sky"), mixRow("Artificial", "artificial"),
        flatButton("Reset Mix", () => { tracer.mix = { sun: 1, sky: 1, artificial: 1 }; renderSide(); void refresh(); }, { compact: true }),
        h("div", { class: "spacer" }), statusEl);
      statusEl.textContent = status;
    };
    async function refresh() {
      const r = await app.tryCall("pathtrace.status", { image: true, mix: tracer.mix, ev, denoise });
      if (!r) return;
      tracer.samples = r.samples;
      if (r.image) { tracer.image = r.image; renderStage(); }
      status = r.status ?? status; statusEl.textContent = status;
      if (tracer.running && !r.running) { tracer.running = false; renderSide(); }
    }
    async function begin() {
      let camera: any = null;
      const v = (window as any).archiView3D;
      if (v) camera = modelCamera(v);
      const r = await app.tryCall("pathtrace.start", { width, height, samples: target, denoise, ev, mix: tracer.mix, ...(camera ? { camera } : {}) });
      if (!r) { status = "Path tracing needs archi-engine."; renderSide(); return; }
      tracer.running = true; tracer.samples = 0; status = r.status; renderSide();
      const my = ++poll;
      while (poll === my && tracer.running && document.body.contains(win.el)) {
        await sleep(500);
        if (poll !== my) break;
        await refresh();
      }
    }
    async function stop() { poll++; await app.tryCall("pathtrace.stop", {}); tracer.running = false; await refresh(); renderSide(); }
    async function save() {
      const p = await saveDialog(app, "Save", "Path Traced.png", [{ name: "PNG", extensions: ["png"] }]);
      if (p) { try { await app.engine.call("pathtrace.save", { path: p }); } catch (e: any) { status = e?.message ?? String(e); renderSide(); } }
    }
    tracer.start = begin;
    renderStage(); renderSide();
    if (start && !tracer.running) void begin();
  }, () => { poll++; void app.tryCall("pathtrace.stop", {}); tracer.running = false; });
}
