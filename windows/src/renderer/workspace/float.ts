// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Floating panels (FloatingPanels.swift, FLOATPANEL): any panel tab can live in its own tool window over the drawing
// window; it leaves the docked tab strip while it floats, the header's dock button (or closing the window) puts it back,
// and the set of floating panels is remembered across launches. Panel windows are the shell's tool windows (partb/ui.ts
// ToolWindow): movable, resizable, with their frames remembered.
import type { App } from "../app";
import { Panels, PANEL_SYMBOLS, floatingTabs } from "../ui/panels";
import { ToolWindow } from "../partb/ui";
import { h } from "../dom";
import { icon } from "../icons";
import { help } from "../ui/menu";

const KEY = "archi.floatingPanels.open";
const TABS = ["Properties", "Layers", "Levels", "Browser", "Materials", "Tools", "Sheets", "History", "Selection", "Navigator", "Alerts", "Quick Props", "Inspector", "Content"];
const instances = new Map<string, Panels>();

function remember() { try { localStorage.setItem(KEY, JSON.stringify([...floatingTabs].sort())); } catch {} }
export function isFloating(tab: string) { return floatingTabs.has(tab); }

/** Floats a panel tab in its own window, or brings its window forward when it already floats (FloatingPanels.float). */
export function floatPanel(app: App, tab: string) {
  if (!TABS.includes(tab)) return;
  const key = "float:" + tab;
  const existing = ToolWindow.get(key);
  if (existing) { existing.front(); return; }
  floatingTabs.add(tab);
  const w = ToolWindow.show(key, tab, { w: 300, h: 520, minW: 240, minH: 240 }, (tw) => {
    const dock = h("button", { class: "iconbtn" }, icon("rectangle.righthalf.inset.filled", 12));
    help(dock, "Dock the panel back into the window");
    dock.addEventListener("click", () => dockPanel(app, tab));
    const head = h("div", { class: "ws-floathead" }, h("span", { class: "sym" }, icon(PANEL_SYMBOLS[tab] ?? "square", 13, 1.7)), h("span", { class: "ttl", text: tab }), h("span", { class: "ws-spacer" }), dock);
    const p = new Panels(app, tab);
    instances.set(tab, p);
    tw.body.classList.add("ws-floatbody");
    tw.body.append(head, h("div", { class: "hsep" }), p.el);
  });
  w.el.classList.add("ws-floatpanel");
  // First time: near the top-right corner of the drawing window, cascaded (FloatingPanels.float), not centred.
  let saved = false;
  try { saved = localStorage.getItem("archi.b.frame." + key) !== null; } catch {}
  if (!saved) {
    const n = floatingTabs.size - 1;
    Object.assign(w.el.style, { left: `${Math.max(20, innerWidth - 320 - 330 - n * 26)}px`, top: `${Math.min(innerHeight - 300, 120 + n * 26)}px` });
  }
  w.onClose = () => dockedBack(app, tab);
  remember();
  if (app.panelTab === tab) { const other = TABS.find((t) => !floatingTabs.has(t)); if (other) app.setUI("panelTab", other); else app.emit("ui"); }
  else app.emit("ui");
}

/** Closes the floating window: the panel returns to the docked column (FloatingPanels.dock). */
export function dockPanel(_app: App, tab: string) { ToolWindow.get("float:" + tab)?.close(); }

function dockedBack(app: App, tab: string) {
  if (!floatingTabs.delete(tab)) return;
  instances.get(tab)?.dispose();
  instances.delete(tab);
  remember();
  app.showPanels = true;
  try { localStorage.setItem("archi.showPanels", "true"); } catch {}
  app.setUI("panelTab", tab);
}

/** Floats the panels that were floating when the app last quit (FloatingPanels.restore). */
export function restoreFloatingPanels(app: App) {
  let names: string[] = [];
  try { names = JSON.parse(localStorage.getItem(KEY) ?? "[]"); } catch {}
  for (const n of names) if (!floatingTabs.has(n)) floatPanel(app, n);
}
