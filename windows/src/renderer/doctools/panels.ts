// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Docked panels that the Mac builds in its UI layer, filled from the engine's document tools (docs/ENGINE-PROTOCOL.md
// "Schedules, browser, text and selection tools"): Project Browser (PanelsView.swift ProjectBrowserPanel), Selection
// (StudioPanels.swift SelectionInfoPanel), Quick Props (AppNavigationViews.swift QuickPropertiesView, docked and the
// compact overlay over the drawing), Inspector (InspectorPanel), History (MaterialHistoryPanels.swift HistoryPanel:
// Undo History / Commands pages, numbered steps, Copy Log) and the Properties type filter menu (PropertiesPanel).
import type { App } from "../app";
import { h, clear } from "../dom";
import { icon } from "../icons";
import { help, showMenu } from "../ui/menu";
import { openSchedule } from "./schedule";

const cap = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s);
/** "wall" → "Wall", "text" → "Text" (Swift String.capitalized). */
export const capitalized = (s: string) => s.split(" ").map(cap).join(" ");

function flat(title: string, onClick: () => void, tip?: string, cls = ""): HTMLButtonElement {
  const b = h("button", { class: "flatbtn dlgbtn compact dt-btn" + (cls ? " " + cls : ""), text: title }) as HTMLButtonElement;
  if (tip) help(b, tip);
  b.addEventListener("click", onClick);
  return b;
}
async function copyText(app: App, text: string) {
  (window as any).archiClipboard = text; // test hook
  try { await navigator.clipboard.writeText(text); return; } catch {}
  const ta = h("textarea", { style: { position: "fixed", left: "-1000px", top: "0" } }) as HTMLTextAreaElement;
  ta.value = text; document.body.append(ta); ta.select();
  const ok = document.execCommand("copy");
  ta.remove();
  if (!ok) app.print("Copy failed: the clipboard is not available.");
}
function zoomTo(app: App, b: number[] | null | undefined) {
  if (!Array.isArray(b) || b.length !== 4) return;
  const pad = Math.max(b[2] - b[0], b[3] - b[1]) * 0.15 + 100;
  if (app.mode === "3D" || app.mode === "Sheet") app.setUI("mode", "2D");
  app.hostView?.zoomTo([b[0] - pad, b[1] - pad, b[2] + pad, b[3] + pad]);
}
async function setSelection(app: App, ids: (number | string)[]) {
  await app.tryCall("select.set", { ids: ids.map((x) => (typeof x === "string" && /^\d+$/.test(x) ? Number(x) : x)) });
  await app.refresh(["selection"]);
}
function show3D(app: App, view: string) {
  if (app.mode === "2D" || app.mode === "Sheet") app.setUI("mode", "3D");
  document.dispatchEvent(new CustomEvent("archi:host", { detail: { action: "setView", view } }));
}

// ---- Project Browser ----
const openSections = new Map<string, boolean>();
export async function renderBrowser(app: App, body: HTMLElement, fresh: () => boolean) {
  const d = await app.tryCall("browser.get", {});
  if (!fresh()) return;
  clear(body);
  if (!d) { body.append(h("div", { class: "pempty", text: "The project browser is not available." })); return; }
  const box = h("div", { class: "dt-browser" });
  const section = (title: string, symbol: string, items: HTMLElement[]) => {
    const open = openSections.get(title) ?? true;
    const head = h("button", { class: "dt-sec" }, icon(open ? "chevron.down" : "chevron.right", 9, 2.4), icon(symbol, 11), h("span", { text: title }));
    head.addEventListener("click", () => { openSections.set(title, !open); void renderBrowser(app, body, () => true); });
    box.append(head);
    if (open) for (const it of items) box.append(it);
  };
  const item = (title: string, symbol: string, active: boolean, act: () => void, tip?: string) => {
    const r = h("button", { class: "dt-item" + (active ? " cur" : "") }, icon(symbol, 10), h("span", { class: "t", text: title }));
    r.addEventListener("click", act);
    if (tip) help(r, tip);
    return r;
  };
  const plan = app.mode !== "Sheet";
  section("Floor Plans", "square.split.bottomrightquarter", (d.levels ?? []).map((l: any) => item(l.name, "square.grid.3x1.below.line.grid.1x2", plan && app.mode !== "3D" && !!l.current, async () => {
    await app.tryCall("panel.set", { panel: "levels", key: "current", value: l.name });
    if (app.mode === "Sheet" || app.mode === "3D") { app.activeLayout = 0; app.setUI("mode", "2D"); }
    await app.refresh(["document"]);
  }, "Click to open · drag onto a sheet to place it at the view scale")));
  const views3d = [...(d.views3d ?? []).map((v: string) => item(`3D — ${v}`, "cube.transparent", false, () => show3D(app, v))),
    ...(d.namedViews ?? []).map((v: any) => item(v.name, v.camera ? "camera" : "eye", false, () => {
      if (v.camera) show3D(app, "named:" + v.name);
      else {
        const hh = Number(v.height ?? 1000), w = hh * 1.6, c = v.center ?? [0, 0];
        app.activeLayout = 0; app.setUI("mode", "2D");
        app.hostView?.zoomTo([c[0] - w / 2, c[1] - hh / 2, c[0] + w / 2, c[1] + hh / 2]);
      }
    }))];
  section("3D Views", "cube", views3d);
  if ((d.projectViews ?? []).length) section("Project Views", "rectangle.stack", d.projectViews.map((v: any) => item(v.label ?? v.name, v.symbol ?? "square.split.bottomrightquarter", !!v.current, async () => {
    const r = await app.tryCall("browser.openView", { name: v.name });
    if (!r) return;
    await app.refresh(["document"]);
    if (r.kind === "3d") {
      if (app.mode === "2D" || app.mode === "Sheet") app.setUI("mode", "3D");
      document.dispatchEvent(new CustomEvent("archi:host", { detail: r.camera ? { action: "view3d", op: "camera", name: v.name, camera: r.camera } : { action: "setView", view: "named:" + v.name } }));
    } else {
      if (app.mode === "Sheet" || app.mode === "3D") { app.activeLayout = 0; app.setUI("mode", "2D"); }
      if (Array.isArray(r.crop)) setTimeout(() => app.hostView?.zoomTo(r.crop), 30);
    }
  }, `Click or double-click to open the view (${v.kind === "3d" ? "3D camera" : v.kind})`)));
  section("Elevations & Sections", "building.columns", (d.elevations ?? []).map((e: any) => item(e.title, e.symbol === "building" ? "building.columns" : e.symbol, false, () => show3D(app, e.view), "Click to look at it in 3D · drag onto a sheet to place it")));
  section("Sheets", "doc.richtext", (d.sheets ?? []).map((s: any) => item(s.name, "doc", app.mode === "Sheet" && app.activeLayout === s.index + 1, () => { app.activeLayout = s.index + 1; app.setUI("mode", "Sheet"); })));
  section("Schedules", "tablecells", (d.schedules ?? []).map((k: string) => item(`${capitalized(k)} Schedule`, "list.bullet.rectangle", false, () => void openSchedule(app, k))));
  if ((d.families ?? []).length) section("Families", "puzzlepiece.extension", d.families.map((f: any) => item(`${f.name} (${f.category})`, "puzzlepiece.extension", false, () => {
    if (!app.uiHooks.host?.({ action: "dialog", dialog: "familyEditor", family: f.name })) void app.runCommand(`FAMILYPANEL ${f.name}`);
  })));
  if ((d.groups ?? []).length) section("Groups", "square.on.square.dashed", d.groups.map((g: any) => item(`${g.name} — ${g.elements} element(s)`, "square.on.square", false, () => void app.runCommand("MODELGROUP"))));
  if ((d.links ?? []).length) section("Links", "link", d.links.map((x: any) => item(`${x.name}${x.overlay ? " (overlay)" : ""}`, "link", false, () => void app.runCommand("XREF"), x.path)));
  body.append(box);
}

// ---- Selection ----
export async function renderSelection(app: App, body: HTMLElement, fresh: () => boolean) {
  const s = await app.tryCall("selection.info", {});
  if (!fresh()) return;
  clear(body);
  const box = h("div", { class: "dt-selection" });
  const total = Number(s?.total ?? 0);
  box.append(h("div", { class: "dt-bold", text: total === 0 ? "Nothing selected" : `${total} object(s) selected` }));
  for (const r of s?.rows ?? []) {
    const row = h("div", { class: "dt-selrow" }, h("span", { class: "ty", text: r.type }), h("span", { class: "n", text: String(r.count) }), h("span", { class: "spacer" }),
      flat("Only", () => void setSelection(app, r.ids), `Keep only the ${r.type} objects selected`),
      flat("Remove", () => void setSelection(app, app.selection.ids.filter((id) => !(r.ids as any[]).map(String).includes(String(id)))), `Remove the ${r.type} objects from the selection`));
    box.append(row);
  }
  if (total > 0) {
    box.append(h("div", { class: "hsep dt-sep" }));
    box.append(h("div", { class: "dt-small", text: "Layers: " + (s.layers ?? []).map((l: any) => `${l.name} (${l.count})`).join(", ") }));
    if (Number(s.length) > 0) box.append(h("div", { class: "dt-mono", text: `Total length ${s.lengthText}` }));
    if (Number(s.area) > 0) box.append(h("div", { class: "dt-mono", text: `Total area ${s.areaText}` }));
    box.append(h("div", { class: "dt-rowbtns" }, flat("Zoom to Selection", () => zoomTo(app, s.bounds)), flat("Clear", () => void setSelection(app, []))));
  }
  body.append(box);
}

// ---- Quick Properties (PropertiesPalette.quickRows) ----
const GENERAL = ["layer", "color", "linetype", "lineweight", "name", "level", "material"];
export function quickRows(rows: any[]): any[] {
  const g = rows.filter((r) => GENERAL.includes(String(r.name).toLowerCase()));
  const rest = rows.filter((r) => !GENERAL.includes(String(r.name).toLowerCase()) && r.name !== "id" && !r.readOnly).slice(0, 6);
  return [...g, ...rest];
}
export async function renderQuick(app: App, body: HTMLElement, fresh: () => boolean, compact = false, onClose?: () => void) {
  const d = app.selection.ids.length ? await app.tryCall("panel.properties", {}) : null;
  if (!fresh()) return;
  clear(body);
  const ids = app.selection.ids;
  const head = h("div", { class: "dt-qphead" }, h("span", { class: "dt-bold", text: ids.length ? `${ids.length} selected` : "No selection" }), h("span", { class: "spacer" }));
  if (compact) {
    const btn = (sym: string, tip: string, act: () => void) => { const b = h("button", { class: "iconbtn" }, icon(sym, 12)); help(b, tip); b.addEventListener("click", act); return b; };
    head.append(btn("sidebar.right", "Dock in the panels (Quick Props tab)", () => { onClose?.(); app.showPanels = true; app.setUI("panelTab", "Quick Props"); app.emit("panel"); }),
      btn("macwindow.on.rectangle", "Float in a window", () => { onClose?.(); void app.runCommand("FLOATPANEL Quick Props"); }),
      btn("xmark", "Hide Quick Properties (QP)", () => onClose?.()));
  }
  const box = h("div", { class: "dt-qp" + (compact ? " compact" : "") }, head);
  const opts: Record<string, string[]> = { layer: app.layers.layers.map((l: any) => l.name), level: (app.info?.levels ?? []).map((l) => String(l.id ?? l.name)) };
  for (const r of quickRows(d?.rows ?? [])) {
    const row = h("div", { class: "dt-qprow" }, h("span", { class: "k", text: capitalized(String(r.name)) }));
    if (r.readOnly) row.append(h("span", { class: "v ro", text: String(r.value ?? "") }));
    else if (opts[r.name]) {
      const b = h("button", { class: "dropfield" }, h("span", { class: "t", text: String(r.value ?? "") }), icon("chevron.down", 10, 2));
      b.addEventListener("click", () => showMenu(opts[r.name].map((o) => ({ title: o, checked: o === r.value, action: () => void apply(app, r.name, o) })), b));
      row.append(b);
    } else {
      const inp = h("input", { class: "darkfield", value: String(r.value ?? "") }) as HTMLInputElement;
      const commit = () => { if (inp.value !== String(r.value ?? "")) void apply(app, r.name, inp.value); };
      inp.addEventListener("keydown", (e) => { e.stopPropagation(); if (e.key === "Enter") { commit(); inp.blur(); } if (e.key === "Escape") { inp.value = String(r.value ?? ""); inp.blur(); } });
      inp.addEventListener("keyup", (e) => e.stopPropagation());
      inp.addEventListener("blur", commit);
      row.append(inp);
    }
    box.append(row);
  }
  if (!compact && !ids.length) box.append(h("div", { class: "dt-small", text: "Select objects to edit their key properties." }));
  body.append(box);
}
async function apply(app: App, name: string, value: string) {
  try { await app.engine.call("panel.set", { panel: "properties", key: name, value }); }
  catch { app.print(`Invalid value for ${name}.`); }
  await app.refresh(["drawing", "properties", "document"]);
}

/** The compact Quick Properties box over the drawing (top right) while objects are selected (QUICKPROPS / QP). */
export class QuickPropsOverlay {
  el = h("div", { class: "dt-qp-overlay" });
  private seq = 0;
  constructor(private app: App) {
    document.body.append(this.el);
    app.on(["selection", "panel", "ui", "doc"], () => this.update());
    addEventListener("resize", () => this.place());
    this.update();
  }
  get on(): boolean { try { return localStorage.getItem("archi.quickProperties") === "true"; } catch { return false; } }
  set on(v: boolean) { try { localStorage.setItem("archi.quickProperties", String(v)); } catch {} this.update(); }
  private place() {
    const ws = document.querySelector(".workspace") as HTMLElement | null;
    if (!ws) return;
    const r = ws.getBoundingClientRect();
    this.el.style.top = r.top + 10 + "px";
    this.el.style.left = r.right - 10 - 260 + "px";
  }
  update() {
    const visible = this.on && this.app.selection.ids.length > 0 && this.app.mode !== "Sheet" && !this.app.cleanScreen;
    this.el.style.display = visible ? "block" : "none";
    if (!visible) return;
    this.place();
    const seq = ++this.seq;
    void renderQuick(this.app, this.el, () => seq === this.seq, true, () => { this.on = false; });
  }
}

// ---- Inspector ----
export async function renderInspector(app: App, body: HTMLElement, fresh: () => boolean) {
  const d = app.selection.ids.length ? await app.tryCall("inspect.get", {}) : null;
  if (!fresh()) return;
  clear(body);
  const box = h("div", { class: "dt-inspector" });
  if (!app.selection.ids.length) box.append(h("div", { class: "dt-dim", text: "Select an object to list all of its data (LIST)." }));
  for (const o of d?.objects ?? []) {
    const card = h("div", { class: "dt-card" });
    for (const [k, v] of o.rows ?? []) card.append(h("div", { class: "dt-kv" + (k === "Geometry" ? " geo" : "") }, h("span", { class: "k", text: k }), h("span", { class: "v", text: v })));
    card.append(flat("Copy", () => void copyText(app, String(o.text ?? "")), "Copy every value as text"));
    box.append(card);
  }
  if (Number(d?.more ?? 0) > 0) box.append(h("div", { class: "dt-small", text: `… and ${d.more} more` }));
  body.append(box);
}

// ---- History ----
let historyPage = 0;
export async function renderHistory(app: App, body: HTMLElement, fresh: () => boolean) {
  const [d, log] = await Promise.all([app.tryCall("panel.history", { limit: 5000 }), historyPage === 1 ? app.tryCall("engine.log", { limit: 5000 }) : Promise.resolve(null)]);
  if (!fresh()) return;
  clear(body);
  const seg = h("div", { class: "segmented dt-seg" });
  ["Undo History", "Commands"].forEach((t, i) => {
    const b = h("button", { class: "seg" + (historyPage === i ? " on" : ""), text: t });
    b.addEventListener("click", () => { historyPage = i; void renderHistory(app, body, () => true); });
    seg.append(b);
  });
  body.append(h("div", { class: "dt-segbar" }, seg), h("div", { class: "hsep" }));
  if (historyPage === 0) {
    const undo: string[] = d?.undo ?? [], redo: string[] = [...(d?.redo ?? [])].reverse();
    const list = h("div", { class: "dt-steps" });
    const step = (index: number, label: string, state: "done" | "current" | "undone") => {
      const r = h("button", { class: "dt-step " + state }, h("span", { class: "n", text: String(index) }), h("span", { class: "dot" }), h("span", { class: "t", text: label }));
      help(r, state === "undone" ? "Redo up to this step" : "Undo back to this step");
      r.addEventListener("click", async () => {
        if (!app.isIdle) { app.print("Finish the current command first."); return; }
        await app.tryCall("history.goto", { index });
        await app.refresh(["drawing", "selection", "history", "document"]);
      });
      list.append(r);
    };
    step(0, "Open / new document", undo.length ? "done" : "current");
    undo.forEach((l, i) => step(i + 1, l, i === undo.length - 1 ? "current" : "done"));
    redo.forEach((l, i) => step(undo.length + i + 1, l, "undone"));
    body.append(list);
  } else {
    // The engine's command history (the Mac commandLog); the window's own log when the engine has none.
    const lines: string[] = log?.lines?.length ? log.lines : app.log;
    const cmds = lines.filter((l) => l.startsWith("Command: ")).map((l) => l.slice(9)).filter((c) => c.trim());
    const list = h("div", { class: "dt-cmds" });
    for (const c of [...cmds].reverse()) {
      const cat = app.lookup(c.split(" ")[0])?.category ?? "";
      const r = h("button", { class: "dt-cmd" }, icon("terminal", 9), h("span", { class: "t", text: c }), h("span", { class: "c", text: cat }));
      help(r, `Run ${c} again`);
      r.addEventListener("click", () => void app.runCommand(c));
      list.append(r);
    }
    body.append(list, h("div", { class: "hsep" }), h("div", { class: "dt-foot" }, h("span", { class: "dt-small", text: `${cmds.length} command(s) this session` }), h("span", { class: "spacer" }),
      flat("Copy Log", () => void copyText(app, lines.join("\n")), "Copy the whole command history")));
  }
}

// ---- Properties: type filter of a mixed selection ----
/** The Mac Properties header: "3 objects (1 door, 2 wall)" with a menu that keeps one object type in the selection. */
export async function typeFilterHeader(app: App): Promise<HTMLElement | null> {
  const s = await app.tryCall("selection.info", {});
  const rows: any[] = s?.rows ?? [];
  if (rows.length < 2) return null;
  const total = rows.reduce((a, r) => a + Number(r.count), 0);
  const counts = [...rows].sort((a, b) => String(a.type).localeCompare(String(b.type)));
  const text = `${total} objects (` + counts.map((r) => `${r.count} ${r.type}`).join(", ") + ")";
  const b = h("button", { class: "dt-typefilter" }, h("span", { text }), icon("chevron.down", 9, 2));
  help(b, "Keep only one object type in the selection");
  b.addEventListener("click", () => showMenu(counts.map((r) => ({ title: `${capitalized(r.type)} (${r.count})`, action: () => void setSelection(app, r.ids) })), b));
  return b;
}
