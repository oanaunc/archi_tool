// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Contextual ribbon tabs, the sheet commands that need the window, crash recovery and file versions (docs/WINDOWS-GAPS.md
// gaps 7, 12, 15, 16). The engine's portable commands (Host/EngineSheetCommands.swift, EngineRecovery.swift) ask for:
//   layoutTabs {on: true|false|null}         LAYOUTTABS: show / hide / toggle the Model and sheet tabs under the canvas
//   paperZoom {ratio, pixelsPerUnit, …}      ZOOMXP / ZOOM nXP: selected sheet viewport to 1:n, or the plan at true size
//   chooseFile {purpose, extensions}         PSETUPIN with Enter: the Open dialog answers the pending prompt
//   sheetImage {layout, dpi, format, path?}  SHEETIMAGE: Save dialog, then sheet.image (JPEG encoded here)
//   recovered, startScreen                   DRAWINGRECOVERY
//   dialog "versions", openWindow {path}     FILEVERSIONS Browse / Open
import "./sheets.css";
import type { App } from "../app";
import { ContextStrip } from "./context-ribbon";
import { afterRecovered, ensureRecoverySetup, recoverySection, recoveryTick, recoveryDiscard, setVersionsKeep, setSaveExtra } from "./recovery";
import { openVersions, openCopyWindow } from "./versions";
import { promptDialog } from "../dialogs/ui";

export { ContextStrip, recoverySection, recoveryTick, recoveryDiscard, openVersions };

// ---- Model / layout tabs (LayoutTabs, AppModel.showLayoutTabs) ----
let showLayoutTabs = (() => { try { return localStorage.getItem("archi.showLayoutTabs") !== "false"; } catch { return true; } })();
export function layoutTabsVisible() { return showLayoutTabs; }
export function setLayoutTabs(app: App, on: boolean) {
  showLayoutTabs = on;
  try { localStorage.setItem("archi.showLayoutTabs", String(on)); } catch {}
  app.emit("ui");
}

export interface SheetsHooks {
  /** The plan canvas (canvas/plan-canvas.ts): its view scale, zoomBy and the selected sheet viewport. */
  plan: any;
}

async function paperZoom(app: App, plan: any, p: any) {
  const ratioText = String(p.ratioText ?? p.ratio);
  const vi: number | null = plan?.selectedViewport ?? null;
  if (app.mode === "Sheet" && vi !== null && app.activeLayout > 0) {
    const r = await app.tryCall("sheet.viewport", { index: vi, op: "scale", ratio: Number(p.ratio), layout: app.info?.layouts[app.activeLayout - 1] });
    if (!r) { app.print("The viewport is locked (VPLOCK Off to unlock)."); return; }
    await app.refresh(["drawing", "history"]);
    app.print(`Viewport ${vi + 1} at 1:${ratioText}.`);
    return;
  }
  if (app.mode === "3D" || app.mode === "Sheet" || !plan?.v?.scale) { app.print("Open the plan view."); return; }
  plan.zoomBy(Number(p.pixelsPerUnit) / plan.v.scale);
  app.print(`Plan shown at 1:${ratioText} on paper, true size on this screen.`);
}

async function chooseFile(app: App, p: any) {
  const exts: string[] = Array.isArray(p.extensions) && p.extensions.length ? p.extensions.map(String) : ["archi"];
  const n = app.engine.native;
  const f = n ? await n.openFileDialog({ title: String(p.title ?? "Open"), filters: [{ name: "Drawings", extensions: exts }] })
    : await promptDialog(String(p.title ?? "Open"), `Path of the drawing (.${exts.join(", .")})`, "", "Open");
  if (f) await app.submitLine(f); else await app.cancel();
}

async function logged(app: App, method: string, params: unknown): Promise<any> {
  try { return await app.engine.call(method, params); } catch (e: any) { app.print(`Error: ${e?.message ?? e}`); return null; }
}

async function saveSheetImage(app: App, p: any) {
  const format = String(p.format ?? "png").toLowerCase();
  const ext = format === "jpeg" || format === "jpg" ? "jpg" : format.startsWith("tif") ? "tiff" : "png";
  const n = app.engine.native;
  let path: string | null = p.path ?? null;
  if (!path) {
    const name = format === "jpeg" ? "JPEG image" : format.startsWith("tif") ? "TIFF image" : "PNG image";
    path = n ? await n.saveFileDialog({ title: "Sheet to Image", defaultPath: String(p.suggested ?? "Sheet." + ext), filters: [{ name, extensions: [ext] }] }) : String(p.suggested ?? "Sheet." + ext);
  }
  if (!path) return;
  const base = { layout: p.layout ?? "Model", dpi: Number(p.dpi ?? 150) };
  if (ext !== "jpg") { await logged(app, "sheet.image", { ...base, format, path }); return; }
  // JPEG: the engine renders a PNG, Chromium encodes it (quality 0.92), the engine writes the file.
  const r = await logged(app, "sheet.image", { ...base, format: "jpeg" });
  if (!r?.png) return;
  const src = n ? n.fileUrl(r.png) : r.png;
  const img = new Image();
  await new Promise<void>((res, rej) => { img.onload = () => res(); img.onerror = () => rej(new Error("Could not render the image (too large?).")); img.src = src; }).catch((e) => { app.print(e.message); });
  if (!img.naturalWidth) return;
  const c = document.createElement("canvas");
  c.width = img.naturalWidth; c.height = img.naturalHeight;
  const g = c.getContext("2d")!;
  g.fillStyle = "#fff"; g.fillRect(0, 0, c.width, c.height); g.drawImage(img, 0, 0);
  const data = c.toDataURL("image/jpeg", 0.92).split(",")[1];
  const w = await logged(app, "view3d.saveImage", { path, data });
  await n?.removeFile?.(r.png);
  if (w) app.print(`Saved ${r.title ?? base.layout} at ${base.dpi} dpi (${r.width}×${r.height} px) to ${w.path ?? path}.`);
}

export function installSheets(app: App, hooks: SheetsHooks) {
  const strip = new ContextStrip(app);
  app.on("doc", () => { void ensureRecoverySetup(app); });
  const prev = app.uiHooks.host;
  app.uiHooks.host = (p: any) => {
    switch (p?.action) {
      case "layoutTabs": setLayoutTabs(app, p.on === null || p.on === undefined ? !showLayoutTabs : !!p.on); return true;
      case "paperZoom": void paperZoom(app, hooks.plan, p); return true;
      case "chooseFile": void chooseFile(app, p); return true;
      case "sheetImage": void saveSheetImage(app, p); return true;
      case "recovered": afterRecovered(app); return true;
      case "openWindow": if (p.path) openCopyWindow(app, String(p.path)); return true;
      case "dialog": if (p.dialog === "versions") { void openVersions(app); return true; } break;
      case "preference":
        if (p.key === "fileVersionsKeep") { setVersionsKeep(Number(p.value)); return true; }
        // FILEPREVIEW Icons / Versions: remembered for the next windows (recovery.setup passes them to the engine).
        if (p.key === "finderPreviewIcons" || p.key === "fileVersionsOnSave") { setSaveExtra(p.key, !!p.value); return true; }
        break;
    }
    return !!prev?.(p);
  };
  (window as any).archiSheets = { strip, openVersions: () => openVersions(app), layoutTabsVisible };
  return { strip };
}
