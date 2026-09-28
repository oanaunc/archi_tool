// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Floating panels (FloatingPanels.swift, FLOATPANEL): any panel tab can live in its own window over the drawing window;
// it leaves the docked tab strip while it floats, the header's dock button (or closing the window) puts it back, and the
// set of floating panels and each window's frame are remembered across launches.
//
// Like the Mac's NSPanel utility windows, each floating panel is a real, separate OS window: the renderer opens it with
// window.open (name "archi-float:<tab>"), and the main process turns that into a BrowserWindow owned by the drawing
// window (main.ts: floatingPanelWindowOptions — stays above it, minimises with it, no taskbar button, shown without
// taking the focus). The panel content is the same Panels view as the docked column, built by this renderer and
// adopted into the new window's document, so it shares the document state, engine and events of its drawing window.
// Where a window cannot be opened (a blocked popup) the panel floats as an in-window tool window instead.
import type { App } from "../app";
import { Panels, PANEL_SYMBOLS, floatingTabs } from "../ui/panels";
import { ToolWindow } from "../partb/ui";
import { h } from "../dom";
import { icon } from "../icons";
import { help, attachMenuWindow } from "../ui/menu";

const KEY = "archi.floatingPanels.open";
const FRAME_KEY = "archi.floatingPanels.frame.";
const TABS = ["Properties", "Layers", "Levels", "Browser", "Materials", "Tools", "Sheets", "History", "Selection", "Navigator", "Alerts", "Quick Props", "Inspector", "Content"];
/** Window name prefix main.ts recognises (setWindowOpenHandler). */
export const FLOAT_WINDOW_PREFIX = "archi-float:";
/** NSPanel(contentRect: 300×520), minimum 240×240 (FloatingPanelView.frame(minWidth:minHeight:)). */
export const FLOAT_SIZE = { w: 300, h: 520, minW: 240, minH: 240 };

interface Floating { tab: string; panels: Panels; front(): void; close(): void; win: Window | null }
const open = new Map<string, Floating>();
let unloading = false;
addEventListener("beforeunload", () => { unloading = true; });
addEventListener("pagehide", () => { unloading = true; for (const f of open.values()) try { f.win?.close(); } catch {} });

function remember() { try { localStorage.setItem(KEY, JSON.stringify([...floatingTabs].sort())); } catch {} }
export function isFloating(tab: string) { return floatingTabs.has(tab); }
/** The OS window of a floating panel (null when it floats in-window or does not float): for tests and the dock button. */
export function floatingWindow(tab: string): Window | null { return open.get(tab)?.win ?? null; }

type Frame = { x: number; y: number; w: number; h: number };
function loadFrame(tab: string): Frame | null {
  try { const f = JSON.parse(localStorage.getItem(FRAME_KEY + tab) ?? "null"); return f && [f.x, f.y, f.w, f.h].every(Number.isFinite) ? f : null; } catch { return null; }
}
function saveFrame(tab: string, w: Window) {
  try {
    if (w.closed || !w.innerWidth) return;
    localStorage.setItem(FRAME_KEY + tab, JSON.stringify({ x: w.screenX, y: w.screenY, w: w.innerWidth, h: w.innerHeight }));
  } catch {}
}

/** Header of a floating panel (FloatingPanelView): accent symbol, bold title, dock button; 28 px on the tab-bar colour. */
function header(app: App, tab: string) {
  const dock = h("button", { class: "iconbtn" }, icon("rectangle.righthalf.inset.filled", 12));
  help(dock, "Dock the panel back into the window");
  dock.addEventListener("click", () => dockPanel(app, tab));
  return h("div", { class: "ws-floathead" }, h("span", { class: "sym" }, icon(PANEL_SYMBOLS[tab] ?? "square", 13, 1.7)), h("span", { class: "ttl", text: tab }), h("span", { class: "ws-spacer" }), dock);
}

/** Floats a panel tab in its own window, or brings its window forward when it already floats (FloatingPanels.float). */
export function floatPanel(app: App, tab: string) {
  if (!TABS.includes(tab)) return;
  const existing = open.get(tab);
  if (existing) { existing.front(); return; }
  floatingTabs.add(tab);
  const cascade = floatingTabs.size - 1;
  const panels = new Panels(app, tab);
  const f = osWindow(app, tab, panels, cascade) ?? inWindow(app, tab, panels, cascade);
  open.set(tab, f);
  remember();
  if (app.panelTab === tab) { const other = TABS.find((t) => !floatingTabs.has(t)); if (other) app.setUI("panelTab", other); else app.emit("ui"); }
  else app.emit("ui");
}

/** A separate OS window (the NSPanel): placed near the drawing window's top-right corner the first time. */
function osWindow(app: App, tab: string, panels: Panels, cascade: number): Floating | null {
  const saved = loadFrame(tab);
  const fr: Frame = saved ?? {
    w: FLOAT_SIZE.w, h: FLOAT_SIZE.h,
    // setFrameTopLeftPoint(x: window.maxX − 320, y: window.maxY − 120), cascaded when several float at once.
    x: Math.round(screenX + outerWidth - 320 - cascade * 26), y: Math.round(screenY + 120 + cascade * 26),
  };
  let win: Window | null = null;
  try { win = window.open("", FLOAT_WINDOW_PREFIX + tab, `popup=yes,width=${Math.round(fr.w)},height=${Math.round(fr.h)},left=${Math.round(fr.x)},top=${Math.round(fr.y)}`); } catch { win = null; }
  if (!win) return null;
  let doc: Document;
  try { doc = win.document; void doc.body; } catch { try { win.close(); } catch {} return null; }
  doc.open(); doc.write("<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>"); doc.close();
  doc.title = tab;
  const base = doc.createElement("base"); base.href = document.baseURI; doc.head.append(base);
  for (const n of document.querySelectorAll('link[rel="stylesheet"], style')) doc.head.append(doc.importNode(n, true));
  // Theme and platform classes (light/dark, win32 …) follow the drawing window.
  const sync = () => {
    doc.documentElement.className = document.documentElement.className;
    for (const a of [...document.documentElement.attributes]) if (a.name.startsWith("data-") || a.name === "style") doc.documentElement.setAttribute(a.name, a.value);
    doc.body.className = document.body.className;
    doc.body.classList.add("ws-floatwin-body");
  };
  sync();
  const mo = new MutationObserver(sync);
  mo.observe(document.documentElement, { attributes: true });
  mo.observe(document.body, { attributes: true, attributeFilter: ["class"] });
  const root = h("div", { class: "ws-floatwin", "data-window": "float:" + tab }, header(app, tab), h("div", { class: "hsep" }), panels.el);
  doc.body.append(root);
  attachMenuWindow(win);
  // The frame is remembered (setFrameAutosaveName) whenever the window is resized, and when it closes.
  let t = 0;
  win.addEventListener("resize", () => { clearTimeout(t); t = window.setTimeout(() => saveFrame(tab, win!), 300); });
  const poll = window.setInterval(() => { if (win!.closed) { clearInterval(poll); return; } saveFrame(tab, win!); }, 2000);
  win.addEventListener("beforeunload", () => {
    saveFrame(tab, win!); clearInterval(poll); mo.disconnect();
    // Closing the window docks the panel (willCloseNotification) — but not when the whole drawing window goes away,
    // so the floating set is restored at the next launch.
    if (!unloading) dockedBack(app, tab);
  });
  return {
    tab, panels, win,
    front: () => { try { win!.focus(); } catch {} },
    close: () => { try { win!.close(); } catch {} if (!unloading) dockedBack(app, tab); },
  };
}

/** Fallback: an in-window tool window (partb/ui.ts ToolWindow). */
function inWindow(app: App, tab: string, panels: Panels, cascade: number): Floating {
  const key = "float:" + tab;
  const w = ToolWindow.show(key, tab, FLOAT_SIZE, (tw) => {
    tw.body.classList.add("ws-floatbody");
    tw.body.append(header(app, tab), h("div", { class: "hsep" }), panels.el);
  });
  w.el.classList.add("ws-floatpanel");
  let saved = false;
  try { saved = localStorage.getItem("archi.b.frame." + key) !== null; } catch {}
  if (!saved) Object.assign(w.el.style, { left: `${Math.max(20, innerWidth - 320 - 330 - cascade * 26)}px`, top: `${Math.min(innerHeight - 300, 120 + cascade * 26)}px` });
  w.onClose = () => dockedBack(app, tab);
  return { tab, panels, win: null, front: () => w.front(), close: () => w.close() };
}

/** Closes the floating window: the panel returns to the docked column (FloatingPanels.dock). */
export function dockPanel(app: App, tab: string) { const f = open.get(tab); if (f) f.close(); else dockedBack(app, tab); }

function dockedBack(app: App, tab: string) {
  const f = open.get(tab);
  open.delete(tab);
  f?.panels.dispose();
  if (!floatingTabs.delete(tab)) return;
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
