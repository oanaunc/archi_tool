// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Output of the Windows shell: plotting and printing (Plot dialog with preview, Print Setup, Publish, Batch Publish,
// plot style tables, PDF export of the sheet or model, SVG sheets), the Render window, RENDERSAVE and RENDERTOFILE,
// the render queue, camera paths, walkthrough / sun-study / turntable videos (MP4), shade-plot renders and the path
// tracer. The engine's output commands ask for these with `host` notifications (docs/ENGINE-PROTOCOL.md "Output").
import "./output.css";
import type { App } from "../app";
import { outCtx, OutputHooks, view3d, renderWindowInfo } from "./context";
import { openPlotPreview, openPrintSetup, printDrawing, hooks as plotHooks, currentTarget, printWith, loadPrintOptions } from "./plot";
import { openBatchPublish, publishWithDialog, sheetSVGWithDialog, openPlotStyles } from "./publish";
import { openRenderWindow } from "./render-window";
import { openRenderQueue } from "./render-queue";
import { openCameraPaths } from "./camera-paths";
import { openPathTrace, tracer } from "./path-trace";
import { exportVideo } from "./videos";
import { renderImage, defaultSettings, alphaMask, RenderSettings, ModelCamera } from "./render";
import { boxes } from "./mp4";
import { writeBytes, encodePixels, saveDialog, out, docName } from "./native";
import { presetNamed } from "../view3d";

export { openPlotPreview, openPrintSetup, openBatchPublish, openPlotStyles, openRenderWindow, openRenderQueue, openCameraPaths, openPathTrace };

export function installOutput(app: App, hooks: OutputHooks) {
  outCtx.app = app;
  outCtx.hooks = hooks;
  (window as any).archiOutputHooks = hooks;
  (window as any).archiPlotTest = { printWith, loadPrintOptions };
  plotHooks.displayBox = () => hooks.displayBox();
  const prevHost = app.uiHooks.host;
  app.uiHooks.host = (p: any) => handleHost(app, p) || !!prevHost?.(p);
  // Export PDF (File ▸ Export ▸ PDF, @export:pdf, EXPORT with Enter): the plot of the sheet or model (FileController).
  const exportAs = app.exportAs.bind(app);
  app.exportAs = async (format: string) => {
    if (format.split(":")[0].toLowerCase() !== "pdf") return exportAs(format);
    const path = await saveDialog(app, "Export PDF", `${docName(app)}.pdf`, [{ name: "PDF", extensions: ["pdf"] }]);
    if (!path) return;
    try {
      const what = currentTarget(app);
      await app.engine.call("plot.pdf", { what, path, quiet: true });
      app.print(`Exported PDF to ${path}`);
    } catch (e: any) { app.print(e?.message ?? String(e)); }
  };
  (window as any).archiOutputTest = { exportVideo, defaultSettings, boxes };
  (window as any).archiOutput = { app, openPlotPreview, openPrintSetup, openBatchPublish, openPlotStyles, openRenderWindow, openRenderQueue, openCameraPaths, openPathTrace, tracer };
}

function handleHost(app: App, p: any): boolean {
  switch (p?.action) {
    case "render": void openRenderWindow(app); return true;
    case "plot": void printDrawing(app); return true;
    case "dialog":
      switch (p.dialog) {
        case "plotPreview": void openPlotPreview(app); return true;
        case "printSetup": void openPrintSetup(app); return true;
        case "batchPublish": void openBatchPublish(app); return true;
        case "plotStyles": void openPlotStyles(app); return true;
        case "renderQueue": void openRenderQueue(app, p.add ?? [], !!p.run); return true;
        case "cameraPaths": void openCameraPaths(app); return true;
        case "pathTrace": void openPathTrace(app, p.start !== false); return true;
        case "render": void openRenderWindow(app); return true;
      }
      return false;
    case "output":
      void runOutput(app, p);
      return true;
  }
  return false;
}

async function site(app: App) {
  const i = await renderWindowInfo(app);
  return { latitude: i.latitude, longitude: i.longitude, northAngle: i.northAngle };
}

async function runOutput(app: App, p: any) {
  try {
    switch (p.op) {
      case "publish": {
        const r = await publishWithDialog(app, { suggested: p.suggested, bookmarks: p.bookmarks !== false, layouts: p.layouts });
        void r;
        return;
      }
      case "sheetSVG": return sheetSVGWithDialog(app, { all: !!p.all, layout: Number(p.layout ?? 0) });
      case "openFile": { const n = out(); if (n) await n.openPath(String(p.path)); else app.print(String(p.path)); return; }
      case "lightMix": tracer.mix = { sun: Number(p.sun), sky: Number(p.sky), artificial: Number(p.artificial) }; return;
      case "renderSave": return renderSave(app, p);
      case "renderToFile": return renderToFile(app, p);
      case "video": return video(app, p);
      case "shadePlotRender": return shadePlotRender(app, p);
    }
  } catch (e: any) { app.print(e?.message ?? String(e)); }
}

/** RENDERSAVE: the photographic preset from the saved camera (or the 3D view's), supersampled, to the PNG. */
async function renderSave(app: App, p: any) {
  const t0 = performance.now();
  const v = await view3d();
  const s: RenderSettings = { ...defaultSettings(), width: Number(p.width), height: Number(p.height), beauty: presetNamed(p.preset) ?? "Daylight", exposure: 0, whiteBalance: 6500 };
  const px = await renderImage(v, { settings: s, site: await site(app), camera: (p.cameraData as ModelCamera) ?? null, supersample: Number(p.supersample ?? 3), verticalCorrection: true });
  await writeBytes(String(p.path), await encodePixels(px));
  const cam = String(p.camera ?? "Current");
  app.print(`Rendered ${p.preset}, ${cam.toLowerCase() === "current" ? "current view" : cam}, ${px.width}×${px.height} (${p.supersample}× supersampled) in ${((performance.now() - t0) / 1000).toFixed(1)} s → ${p.path}`);
}

/** RENDERTOFILE Beauty / Alpha: the last Render window preset, a region, a style. */
async function renderToFile(app: App, p: any) {
  const v = await view3d();
  const info = await renderWindowInfo(app);
  const s = defaultSettings();
  const last = (() => { try { return localStorage.getItem("archi.render.lastPreset"); } catch { return null; } })();
  const preset = (info.presets ?? []).find((x: any) => x.name === last);
  if (preset) { const { applyPreset } = await import("./render"); applyPreset(preset, s); }
  s.width = Number(p.width); s.height = Number(p.height);
  if (p.pass === "Alpha") s.background = "Transparent";
  let px = await renderImage(v, { settings: s, site: { latitude: info.latitude, longitude: info.longitude, northAngle: info.northAngle }, camera: p.camera ?? null, region: p.region ?? null, style: p.pass === "Beauty" ? p.style : "Photographic" });
  if (p.pass === "Alpha") px = alphaMask(px);
  await writeBytes(String(p.path), await encodePixels(px));
  const region = p.region ? ` (region of ${p.width}×${p.height})` : "";
  app.print(`${p.pass} ${px.width}×${px.height}${region} → ${p.path}`);
}

/** WALKTHROUGHVIDEO / SUNSTUDYVIDEO: 1280×720 frames at 30 fps (RenderSettings defaults), asking for the file when needed. */
async function video(app: App, p: any) {
  let path: string | null = p.path ?? null;
  if (!path) path = await saveDialog(app, "Export Video", String(p.suggested ?? `${docName(app)}.mp4`), [{ name: "MPEG-4 movie", extensions: ["mp4"] }]);
  if (!path) return;
  const s = { ...defaultSettings(), width: Number(p.width ?? 1280), height: Number(p.height ?? 720) };
  await exportVideo(app, { kind: p.kind, settings: s, site: await site(app), path, seconds: Number(p.seconds ?? 10), fps: Number(p.fps ?? 30), day: p.day, fromHour: p.fromHour, toHour: p.toHour, camera: p.camera ?? null });
  app.print(`Saved ${path}`);
}

/** SHADEPLOT Rendered: a raster render of the 3D viewport's camera, stored for the sheet (ShadePlot.renderImage). */
async function shadePlotRender(app: App, p: any) {
  const v = await view3d();
  const aspect = Number(p.aspect ?? 1.5);
  const maxPx = 2400;
  const w = aspect >= 1 ? maxPx : Math.max(16, Math.round(maxPx * aspect)), hh = aspect >= 1 ? Math.max(16, Math.round(maxPx / aspect)) : maxPx;
  const s = { ...defaultSettings(), width: w, height: hh, background: "White" as const };
  const px = await renderImage(v, { settings: s, site: await site(app), camera: p.camera ?? null, verticalCorrection: false });
  const png = await encodePixels(px);
  const n = out();
  const dir = n ? (await n.folders()).temp : "tmp";
  const path = `${dir}\\ArchiShadePlot-${String(p.layout).replace(/[^A-Za-z0-9]+/g, "_")}-${p.index}.png`;
  await writeBytes(path, png);
  await app.tryCall("plot.shadePlotImage", { layout: p.layout, index: p.index, path });
  await app.refresh(["document", "drawing"]);
}
