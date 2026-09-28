// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Document tools: the Schedule sheet, Spelling dialog, Text Styles window, the in-place text editor command
// (TEXTEDITINPLACE), Quick Properties over the drawing (QUICKPROPS / QP), and the docked Project Browser, Selection,
// Quick Props, Inspector and History panels (doctools/panels.ts). The engine's portable commands ask for them with
// `host` notifications; ribbon items with the Mac `ui` target "sheet:schedule" open the Schedule sheet directly.
import "./doctools.css";
import type { App } from "../app";
import { openSchedule } from "./schedule";
import { openSpelling } from "./spelling";
import { openTextStyles } from "./textstyles";
import { QuickPropsOverlay, renderBrowser, renderSelection, renderQuick, renderInspector, renderHistory, typeFilterHeader } from "./panels";

export { openSchedule, openSpelling, openTextStyles, typeFilterHeader };

/** Panel tabs drawn by this module (ui/panels.ts asks here first). */
export const DOC_PANELS: Record<string, (app: App, body: HTMLElement, fresh: () => boolean) => Promise<void>> = {
  Browser: renderBrowser, Selection: renderSelection, "Quick Props": (a, b, f) => renderQuick(a, b, f), Inspector: renderInspector, History: renderHistory,
};

export interface DocToolsHooks { editText(id: number): void }

export function installDocTools(app: App, hooks: DocToolsHooks) {
  // The window has Chromium's spell checker on for the Spelling dialog (preload/spell.ts); no red underlines in fields.
  document.documentElement.setAttribute("spellcheck", "false");
  const qp = new QuickPropsOverlay(app);
  (window as any).archiDocTools = { openSchedule: (k?: string) => openSchedule(app, k), openSpelling: () => openSpelling(app), openTextStyles: () => openTextStyles(app), quickProps: qp };
  const prevHost = app.uiHooks.host;
  app.uiHooks.host = (p: any) => {
    switch (p?.action) {
      case "dialog":
        if (p.dialog === "spelling") { void openSpelling(app); return true; }
        if (p.dialog === "textStyles") { void openTextStyles(app); return true; }
        if (p.dialog === "schedule") { void openSchedule(app, String(p.kind ?? "all")); return true; }
        break;
      case "quickProps": qp.on = p.mode === "on" ? true : p.mode === "off" ? false : !qp.on; return true;
      case "textEditor":
        if (app.mode === "3D" || app.mode === "Sheet") { app.activeLayout = 0; app.setUI("mode", "2D"); }
        setTimeout(() => hooks.editText(Number(p.id)), 30);
        return true;
      case "showPanel": {
        // FileController.showPanel: "schedule(s)" is the Schedule sheet on the Mac.
        const n = String(p.panel ?? "").toLowerCase();
        if (n === "schedule" || n === "schedules") { void openSchedule(app, "all"); return true; }
        if (n === "quickproperties" || n === "qp" || n === "quickprops") { qp.on = true; return true; }
        break;
      }
    }
    return !!prevHost?.(p);
  };
  const prevUI = app.uiHooks.ui;
  app.uiHooks.ui = (ref: string) => {
    if (ref === "sheet:schedule") { void openSchedule(app, "all"); return true; }
    if (ref === "sheet:spelling") { void openSpelling(app); return true; }
    if (ref === "window:TextStylesPanel") { void openTextStyles(app); return true; }
    return !!prevUI?.(ref);
  };
}
