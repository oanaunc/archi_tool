// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The Alerts (NotificationsPanel), Navigator (NavigatorPanel) and Content (DesignCenterPanel) panels of the Mac
// (StudioPanels.swift, AppNavigationViews.swift), drawn from the engine's alerts.get, navigator.get and content.* data.
// ui/panels.ts asks here first for these tabs; floating panels (workspace/float.ts) use the same renderers.
import type { App } from "../app";
import { h, clear } from "../dom";
import { icon } from "../icons";
import { help, showMenu } from "../ui/menu";
import { WS } from "./native";

export interface PlanHooks { visibleBox(): [number, number, number, number] | null; centre(x: number, y: number): void; zoomTo(r: [number, number, number, number]): void }
export const planHooks: { current: PlanHooks | null } = { current: null };

// ---- Alerts ----

const alertState = { showInfo: false, dismissed: new Set<string>() };

/** Selects the objects of an alert and zooms to them on their level (NotificationsPanel.zoom / ReviewUI.zoom). */
export async function zoomToAlert(app: App, it: any) {
  const ids = (it.ids ?? []) as number[];
  await app.tryCall("select.set", { ids });
  if (it.level !== null && it.level !== undefined) {
    const lv = app.info?.levels.find((l: any) => l.id === it.level);
    if (lv && lv.name !== app.info?.currentLevel) await app.tryCall("panel.set", { panel: "levels", key: "current", value: lv.name });
  }
  if (app.mode === "3D" || app.mode === "Sheet") { app.activeLayout = 0; app.setUI("mode", "2D"); }
  await app.refresh(["selection", "document"]);
  const b = it.bounds as number[] | null;
  if (b && b.length === 4) {
    const m = Math.max(b[2] - b[0], b[3] - b[1], 1000) * 0.25;
    setTimeout(() => planHooks.current?.zoomTo([b[0] - m, b[1] - m, b[2] + m, b[3] + m]), 30);
  }
}

export async function renderAlerts(app: App, body: HTMLElement, fresh: () => boolean) {
  const d = await app.tryCall("alerts.get", { showInfo: alertState.showInfo, dismissed: [...alertState.dismissed] });
  if (!fresh()) return;
  clear(body);
  const items: any[] = d?.items ?? [];
  const wrap = h("div", { class: "ws-alerts" });
  const info = h("input", { type: "checkbox" }) as HTMLInputElement;
  info.checked = alertState.showInfo;
  info.addEventListener("change", () => { alertState.showInfo = info.checked; void renderAlerts(app, body, fresh); });
  const head = h("div", { class: "ws-row ws-head" }, h("span", { class: "ws-bold", text: items.length ? `${items.length} notification(s)` : "No warnings" }), h("span", { class: "ws-spacer" }),
    h("label", { class: "ws-check" }, info, h("span", { text: "Info" })));
  if (alertState.dismissed.size) {
    const restore = h("button", { class: "flatbtn compact", text: "Restore dismissed" });
    restore.addEventListener("click", () => { alertState.dismissed.clear(); void renderAlerts(app, body, fresh); });
    head.append(restore);
  }
  wrap.append(head);
  const list = h("div", { class: "ws-list" });
  for (const it of items) {
    const sev = String(it.severity);
    const sym = sev === "error" ? "xmark.octagon.fill" : sev === "warning" ? "exclamationmark.triangle.fill" : "info.circle";
    const ids = (it.ids ?? []).slice(0, 6).map((x: number) => `#${x}`).join(" ");
    const dismiss = h("button", { class: "iconbtn" }, icon("xmark", 11, 2));
    help(dismiss, "Dismiss");
    dismiss.addEventListener("click", (e) => { e.stopPropagation(); alertState.dismissed.add(String(it.key)); void renderAlerts(app, body, fresh); });
    const row = h("div", { class: "ws-alert " + sev, "data-key": String(it.key) },
      h("span", { class: "sev" }, icon(sym, 13, 1.8)),
      h("div", { class: "txt" }, h("div", { class: "msg", text: String(it.message) }), h("div", { class: "code", text: String(it.code) + (ids ? " · " + ids : "") })),
      dismiss);
    help(row, "Click to zoom to the objects and select them");
    row.addEventListener("click", () => void zoomToAlert(app, it));
    list.append(row);
  }
  wrap.append(list);
  body.append(wrap);
}

// ---- Navigator ----

interface NavData { lines: number[][]; extents: number[] | null; level?: number }
let navCache: { stamp: number; data: NavData } | null = null;
let navStamp = 0;
let navTimer: number | null = null;

/** Uniform fit of an extent in a map (NavigatorMap.fit): scale and offsets. */
export function navFit(ext: number[], w: number, hh: number, margin = 8) {
  const ew = Math.max(ext[2] - ext[0], 1e-9), eh = Math.max(ext[3] - ext[1], 1e-9);
  const s = Math.min((w - 2 * margin) / ew, (hh - 2 * margin) / eh);
  return { s, ox: (w - ew * s) / 2 - ext[0] * s, oy: (hh - eh * s) / 2 - ext[1] * s };
}

export function invalidateNavigator() { navStamp++; }

export async function renderNavigator(app: App, body: HTMLElement, fresh: () => boolean) {
  if (!navCache || navCache.stamp !== navStamp) {
    const d = await app.tryCall("navigator.get", {});
    if (!fresh()) return;
    navCache = { stamp: navStamp, data: d ?? { lines: [], extents: null } };
  }
  clear(body);
  const cv = h("canvas", { class: "ws-nav" }) as HTMLCanvasElement;
  help(cv, "Drag to move the view rectangle");
  const box = h("div", { class: "ws-navbox" }, cv);
  body.append(box);
  const data = navCache.data;
  const extent = () => {
    const e = data.extents ? [...data.extents] : [0, 0, 10000, 10000];
    const v = planHooks.current?.visibleBox();
    if (v) { e[0] = Math.min(e[0], v[0]); e[1] = Math.min(e[1], v[1]); e[2] = Math.max(e[2], v[2]); e[3] = Math.max(e[3], v[3]); }
    return e;
  };
  const paint = () => {
    if (!cv.isConnected) { if (navTimer) { clearInterval(navTimer); navTimer = null; } return; }
    const w = box.clientWidth || 260, hh = Math.max(180, box.clientHeight || 220), dpr = devicePixelRatio || 1;
    if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(hh * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(hh * dpr); cv.style.width = w + "px"; cv.style.height = hh + "px"; }
    const ctx = cv.getContext("2d");
    if (!ctx) return;
    const f = navFit(extent(), w, hh);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const css = getComputedStyle(document.documentElement);
    ctx.fillStyle = css.getPropertyValue("--canvas").trim() || "#1E1F22";
    ctx.fillRect(0, 0, w, hh);
    ctx.strokeStyle = css.getPropertyValue("--dim").trim() || "#9A9BA1";
    ctx.lineWidth = 0.6;
    ctx.beginPath();
    for (const l of data.lines) {
      for (let i = 0; i + 1 < l.length; i += 2) {
        const x = l[i] * f.s + f.ox, y = hh - (l[i + 1] * f.s + f.oy);
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
    }
    ctx.stroke();
    const v = planHooks.current?.visibleBox();
    if (v) {
      const x0 = v[0] * f.s + f.ox, x1 = v[2] * f.s + f.ox, y0 = hh - (v[3] * f.s + f.oy), y1 = hh - (v[1] * f.s + f.oy);
      const accent = css.getPropertyValue("--accent").trim() || "#F5C518";
      ctx.globalAlpha = 0.12; ctx.fillStyle = accent; ctx.fillRect(x0, y0, x1 - x0, y1 - y0);
      ctx.globalAlpha = 1; ctx.strokeStyle = accent; ctx.lineWidth = 1.5; ctx.strokeRect(x0, y0, x1 - x0, y1 - y0);
    }
  };
  const toWorld = (e: MouseEvent) => {
    const r = cv.getBoundingClientRect();
    const f = navFit(extent(), r.width, r.height);
    return [(e.clientX - r.left - f.ox) / f.s, (r.height - (e.clientY - r.top) - f.oy) / f.s];
  };
  cv.addEventListener("mousedown", (e) => {
    const go = (ev: MouseEvent) => { const p = toWorld(ev); planHooks.current?.centre(p[0], p[1]); paint(); };
    go(e);
    const up = () => { removeEventListener("mousemove", go); removeEventListener("mouseup", up); };
    addEventListener("mousemove", go); addEventListener("mouseup", up);
    e.preventDefault();
  });
  requestAnimationFrame(paint);
  if (navTimer) clearInterval(navTimer);
  navTimer = window.setInterval(paint, 250);
}

// ---- Content (Design Center) ----

const content = { path: "", name: "", kinds: [] as { kind: string; symbol: string; names: string[] }[], kind: "Blocks", chosen: new Set<string>(), message: "" };
const KINDS: [string, string][] = [["Blocks", "square.on.square.dashed"], ["Layers", "square.3.layers.3d"], ["Linetypes", "line.3.horizontal"], ["Text Styles", "textformat"],
  ["Dimension Styles", "ruler"], ["Materials", "paintpalette"]];

async function loadContent(app: App, path: string, name?: string) {
  const r = await app.tryCall("content.scan", { path });
  if (!r) { content.message = `Cannot read ${path.split(/[\\/]/).pop()}.`; return; }
  content.path = path; content.name = name ?? r.name; content.kinds = r.kinds ?? []; content.chosen.clear(); content.message = "";
}
async function chooseFile(app: App): Promise<string | null> {
  const n = app.engine.native;
  if (n) return n.openFileDialog({ title: "Choose Drawing", filters: [{ name: "Drawings", extensions: ["archi", "dxf", "dwg", "ifc"] }] });
  return window.prompt("Drawing file (.archi)", "Cedar House.archi");
}

export async function renderContent(app: App, body: HTMLElement, fresh: () => boolean) {
  const others = (await WS.windows()).filter((w) => !w.focused && w.path);
  if (!fresh()) return;
  clear(body);
  const rerender = () => void renderContent(app, body, fresh);
  const wrap = h("div", { class: "ws-content" });
  const choose = h("button", { class: "dropfield ws-choose" }, h("span", { class: "t", text: content.name || "Choose Drawing" }), icon("chevron.down", 10, 2));
  choose.addEventListener("click", () => showMenu([
    ...others.map((w) => ({ title: `Open window: ${w.title}`, action: async () => { await loadContent(app, w.path!, w.title); rerender(); } })),
    ...(others.length ? [{ separator: true } as any] : []),
    { title: "Drawing File…", action: async () => { const p = await chooseFile(app); if (p) { await loadContent(app, p); rerender(); } } },
  ], choose));
  const kind = h("select", { class: "ws-kind" }) as HTMLSelectElement;
  for (const [k] of KINDS) { const o = h("option", { value: k, text: k }) as HTMLOptionElement; o.selected = k === content.kind; kind.append(o); }
  kind.addEventListener("change", () => { content.kind = kind.value; content.chosen.clear(); rerender(); });
  wrap.append(h("div", { class: "ws-row" }, choose), h("div", { class: "ws-row" }, h("span", { class: "ws-kindicon" }, icon(KINDS.find((k) => k[0] === content.kind)?.[1] ?? "square", 12)), kind));
  if (content.path) {
    const names = content.kinds.find((k) => k.kind === content.kind)?.names ?? [];
    const list = h("div", { class: "ws-list ws-names" });
    for (const n of names) {
      const row = h("div", { class: "li" + (content.chosen.has(n) ? " cur" : ""), text: n });
      row.addEventListener("click", (e) => { if (!(e.ctrlKey || e.shiftKey)) { const had = content.chosen.has(n) && content.chosen.size === 1; content.chosen.clear(); if (!had) content.chosen.add(n); } else if (content.chosen.has(n)) content.chosen.delete(n); else content.chosen.add(n); rerender(); });
      list.append(row);
    }
    if (!names.length) list.append(h("div", { class: "pempty", text: `No ${content.kind.toLowerCase()} in ${content.name}.` }));
    const add = async (all: boolean) => {
      const r = await app.tryCall("content.add", { path: content.path, kind: content.kind, names: [...content.chosen], all });
      content.message = r?.message ?? content.message;
      await app.refresh(["document", "layers"]);
      rerender();
    };
    const addBtn = h("button", { class: "flatbtn prominent", text: "Add to Drawing" }) as HTMLButtonElement;
    addBtn.disabled = content.chosen.size === 0;
    addBtn.addEventListener("click", () => void add(false));
    const allBtn = h("button", { class: "flatbtn", text: "Add All" });
    allBtn.addEventListener("click", () => void add(true));
    wrap.append(list, h("div", { class: "ws-row" }, addBtn, allBtn));
  } else {
    wrap.append(h("div", { class: "psub", text: "Browse the blocks, layers, linetypes, styles and materials of another drawing and add them to this one (ADCENTER)." }));
  }
  if (content.message) wrap.append(h("div", { class: "psub ws-msg", text: content.message }));
  body.append(wrap);
}

/** Panel tabs drawn by this module (ui/panels.ts asks here first). */
export const WS_PANELS: Record<string, (app: App, body: HTMLElement, fresh: () => boolean) => Promise<void>> = {
  Alerts: renderAlerts, Navigator: renderNavigator, Content: renderContent,
};
