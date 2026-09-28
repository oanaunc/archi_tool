// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Graphic standards, clipboard and sharing (Host/EngineStandardsCommands.swift asks for these with `host`
// notifications, docs/ENGINE-PROTOCOL.md "Graphic standards, clipboard and sharing"):
//   dialogs graphicStyles, objectStyles, matPatterns, imageAdjust · visualStyle (custom visual styles in the 3D view)
//   · preference lwDisplayScale · pasteSpecial · copyPicture · share · openFile · speak.
// The shell tells the engine what its commands need with ui.prefs: viewMode (SPEAKDRAWING), lwDisplayScale,
// clipboardExternal (PASTESPECIAL) and nodePackagesFolder (NODEPACKAGE).
import "./standards.css";
import type { App } from "../app";
import { openGraphicStyles } from "./graphic-styles";
import { openObjectStyles, openMatPatterns, openImageAdjust } from "./dialogs";
import { pasteSpecial, copyPicture, clipboardHasExternal } from "./clipboard";
import { shareFiles, openFile } from "./share";
import { speak } from "./speech";
import { lwDisplayScale, setLwDisplayScale } from "./lwscale";
import { std } from "./native";
import { paths as partbPaths } from "../partb/native";

export { lwDisplayScale } from "./lwscale";
export { openGraphicStyles, openObjectStyles, openMatPatterns, openImageAdjust };

/** Custom visual styles of the drawing (VISUALSTYLES), for the Visual Style menus. */
export interface CustomVisualStyle { name: string; base: string; edges: boolean | null; edgeColor: string | null; faceOpacity: number | null; shadows: boolean | null; background: string | null }
export const visualStyles: { custom: CustomVisualStyle[]; current: CustomVisualStyle | null } = { custom: [], current: null };
(window as any).archiVisualStyles = visualStyles;

export function installStandards(app: App) {
  const prevHost = app.uiHooks.host;
  app.uiHooks.host = (p: any) => {
    switch (p?.action) {
      case "dialog":
        if (p.dialog === "graphicStyles") { void openGraphicStyles(app); return true; }
        if (p.dialog === "objectStyles") { void openObjectStyles(app); return true; }
        if (p.dialog === "matPatterns") { void openMatPatterns(app); return true; }
        if (p.dialog === "imageAdjust") { void openImageAdjust(app, (p.ids ?? []).map(Number)); return true; }
        break;
      case "preference":
        if (p.key === "lwDisplayScale") { setLwDisplayScale(Number(p.value)); app.canvas?.refresh(); app.emit("drawing"); return true; }
        break;
      case "visualStyle": applyVisualStyle(app, p); return true;
      case "pasteSpecial": void pasteSpecial(app, Number(p.x), Number(p.y)); return true;
      case "copyPicture": void copyPicture(app, p); return true;
      case "share": void shareFiles(app, (p.paths ?? []).map(String)); return true;
      case "openFile": void openFile(app, String(p.path ?? "")); return true;
      case "speak": speak(String(p.text ?? "")); return true;
    }
    return !!prevHost?.(p);
  };

  // Settings the engine's commands read (ui.prefs).
  let timer = 0;
  const sync = () => {
    clearTimeout(timer);
    timer = window.setTimeout(async () => {
      const values: Record<string, string> = { viewMode: app.mode, lwDisplayScale: String(lwDisplayScale()), clipboardExternal: (await clipboardHasExternal()) ? "1" : "0" };
      if (app.engine.native) { try { values.nodePackagesFolder = (await partbPaths()).nodePackages; } catch { /* no paths */ } }
      await app.tryCall("ui.prefs", { values });
    }, 50);
  };
  app.on(["ui", "doc", "start"], sync);
  addEventListener("focus", sync);
  document.addEventListener("copy", () => setTimeout(sync, 100));
  sync();

  // Custom visual styles for the Visual Style menus.
  const loadStyles = async () => {
    const r = await app.tryCall("visualstyles.list", {});
    visualStyles.custom = r?.custom ?? [];
    if (visualStyles.current && !visualStyles.custom.some((c) => c.name === visualStyles.current!.name)) visualStyles.current = null;
    app.emit("ui");
  };
  app.on(["doc", "history"], () => void loadStyles());
  void loadStyles();
  (window as any).archiStandards = { openGraphicStyles: () => openGraphicStyles(app), openObjectStyles: () => openObjectStyles(app), openMatPatterns: () => openMatPatterns(app), native: std };
}

/** VISUALSTYLES Current: the 3D view shows the style (a custom style = its base plus overrides); plan and sheet
 *  windows switch to the 3D model like the Mac. */
function applyVisualStyle(app: App, p: any) {
  const custom: CustomVisualStyle | null = p.custom ?? null;
  visualStyles.current = custom;
  (window as any).archiVisualStyleCustom = custom;
  if (app.mode === "2D" || app.mode === "Sheet") app.setUI("mode", "3D");
  document.dispatchEvent(new CustomEvent("archi:host", { detail: { action: "setViewStyle", style: String(p.base ?? p.name ?? "Shaded"), custom, name: String(p.name ?? "") } }));
  app.emit("ui");
}
