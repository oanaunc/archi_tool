// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Tool palettes (ToolPalette.swift ToolPalettePanel, TOOLPALETTES): the Draw, Modify, Annotate and Build command tiles,
// the drawing's Blocks and the component library with line thumbnails (click, then click in the drawing to place —
// Space rotates 90° — or drag onto the drawing), and My Tools (add with the field or "Add to My Tools", drag in from the
// other palettes, drag to reorder, right-click to remove). Stored like the Mac @AppStorage keys toolPalette.custom/tab.
import type { App } from "../app";
import { h, clear } from "../dom";
import { icon } from "../icons";
import { help, showMenu } from "../ui/menu";
import paletteData from "../data/palettes.generated.json";
import uiData from "../data/ui.generated.json";
import { Panels } from "../ui/panels";

export const DROP_TYPE = "text/plain";
export const PREFIX = { block: "archi-block:", component: "archi-component:", command: "archi-command:", material: "archi-material:", libraryBlock: "archi-libblock:" };
interface PaletteItem { title: string; symbol: string; command: string; names?: string[]; args?: string }
interface Palette { name: string; kind: string; items?: PaletteItem[]; default?: string[] }
const PALETTES: Palette[] = (paletteData as any).palettes ?? [];
const DEFAULT_CUSTOM = "WALL,DOOR,WINDOW,ROOM,DIMLINEAR,HATCH";

function load(key: string, def: string): string { try { return localStorage.getItem("archi.toolPalette." + key) ?? def; } catch { return def; } }
function save(key: string, v: string) { try { localStorage.setItem("archi.toolPalette." + key, v); } catch {} }

/** Symbol of a command for My Tools (QuickAccess.symbol): the palette or ribbon item that runs it. */
let symbolIndex: Map<string, string> | null = null;
export function symbolFor(cmd: string): string {
  if (!symbolIndex) {
    symbolIndex = new Map();
    for (const p of PALETTES) for (const i of p.items ?? []) for (const n of [i.command, ...(i.names ?? [])]) if (!symbolIndex.has(n)) symbolIndex.set(n, i.symbol);
    const walk = (v: any) => { if (Array.isArray(v)) v.forEach(walk); else if (v && typeof v === "object") { if (typeof v.command === "string" && typeof v.symbol === "string" && !symbolIndex!.has(v.command)) symbolIndex!.set(v.command, v.symbol); Object.values(v).forEach(walk); } };
    walk((uiData as any).ribbon);
  }
  return symbolIndex.get(cmd.toUpperCase()) ?? "terminal";
}

let itemsCache: { blocks: any[]; components: any[] } | null = null;
let itemsFor = "";

/** Renders the Tools panel into `body`. */
export function renderToolPalette(app: App, body: HTMLElement) {
  let tab = load("tab", "Draw");
  let custom = load("custom", DEFAULT_CUSTOM).split(",").filter(Boolean);
  const names = [...PALETTES.filter((p) => p.kind === "commands").map((p) => p.name), "Blocks", "Components", "My Tools"];
  if (!names.includes(tab)) tab = "Draw";
  const root = h("div", { class: "tool-palette" });
  body.append(root);
  const setCustom = (list: string[]) => { custom = list; save("custom", list.join(",")); render(); };
  const resolve = (item: PaletteItem): string | null => {
    for (const n of item.names ?? [item.command]) if (app.lookup(n)) return app.lookup(n)!.name;
    return app.lookup(item.command)?.name ?? null;
  };

  function render() {
    clear(root);
    const tabs = h("div", { class: "tp-tabs" });
    for (const t of names) {
      const b = h("button", { class: "tp-tab" + (t === tab ? " sel" : ""), text: t });
      b.addEventListener("click", () => { tab = t; save("tab", t); render(); });
      tabs.append(b);
    }
    const grid = h("div", { class: "tp-grid" });
    const scroller = h("div", { class: "tp-scroll" }, grid);
    root.append(h("div", { class: "tp-tabbar" }, tabs), h("div", { class: "hsep" }), scroller);
    if (tab === "Blocks" || tab === "Components") void shapeTiles(grid, tab);
    else if (tab === "My Tools") myTools(grid);
    else for (const item of PALETTES.find((p) => p.name === tab)?.items ?? []) {
      const r = resolve(item);
      const t = tile(item.title, item.symbol, r ? app.lookup(r)?.summary ?? "" : "Not available in this build", !!r, () => { if (r) app.runCommand(item.args ? `${r} ${item.args}` : r); });
      draggable(t, PREFIX.command + (r ?? item.command));
      t.addEventListener("contextmenu", (e) => {
        e.preventDefault();
        showMenu([{ title: "Add to My Tools", disabled: !r || custom.includes(r), action: () => { if (r && !custom.includes(r)) setCustom([...custom, r]); } }], { x: e.clientX, y: e.clientY });
      });
      grid.append(t);
    }
    // My Tools accepts tiles dragged from the other palettes anywhere in the panel.
    scroller.addEventListener("dragover", (e) => { if (tab === "My Tools") { e.preventDefault(); e.dataTransfer!.dropEffect = "copy"; } });
    scroller.addEventListener("drop", (e) => {
      if (tab !== "My Tools") return;
      const s = e.dataTransfer?.getData(DROP_TYPE) ?? "";
      if (!s.startsWith(PREFIX.command)) return;
      e.preventDefault();
      const n = s.slice(PREFIX.command.length);
      if (!custom.includes(n)) setCustom([...custom, n]);
    });
    if (tab === "My Tools") {
      const inp = h("input", { class: "pfield", placeholder: "Add command (e.g. OFFSET)", spellcheck: false }) as HTMLInputElement;
      const add = () => {
        const d = app.lookup(inp.value.trim());
        if (!d) { inp.classList.add("shake"); setTimeout(() => inp.classList.remove("shake"), 300); return; }
        if (!custom.includes(d.name)) setCustom([...custom, d.name]); else render();
      };
      inp.addEventListener("keydown", (e) => { e.stopPropagation(); if (e.key === "Enter") add(); });
      const b = h("button", { class: "flatbtn compact", text: "Add" }); b.addEventListener("click", add);
      root.append(h("div", { class: "hsep" }), h("div", { class: "tp-add" }, inp, b));
    }
    root.append(h("div", { class: "hsep" }), h("div", { class: "tp-hint", text: tab === "My Tools" ? "Drag tiles here from other palettes · drag within to reorder" : "Click to start · drag onto the drawing · right-click to add to My Tools" }));
  }

  function tile(title: string, symbol: string, tip: string, enabled: boolean, act: () => void) {
    const b = h("button", { class: "tp-tile" + (enabled ? "" : " disabled") }, h("span", { class: "tp-ico" }, icon(symbol, 17)), h("span", { class: "tp-title", text: title })) as HTMLButtonElement;
    help(b, tip);
    b.addEventListener("click", () => { if (enabled) act(); });
    return b;
  }
  function draggable(el: HTMLElement, payload: string) {
    el.draggable = true;
    el.addEventListener("dragstart", (e) => { e.dataTransfer?.setData(DROP_TYPE, payload); if (e.dataTransfer) e.dataTransfer.effectAllowed = "copy"; });
  }
  function myTools(grid: HTMLElement) {
    for (const n of custom) {
      const d = app.lookup(n);
      const t = tile(n.charAt(0) + n.slice(1).toLowerCase(), symbolFor(n), d?.summary ?? "Not available", !!d, () => app.runCommand(n));
      draggable(t, PREFIX.command + n);
      t.addEventListener("dragover", (e) => { e.preventDefault(); e.stopPropagation(); });
      t.addEventListener("drop", (e) => {
        const s = e.dataTransfer?.getData(DROP_TYPE) ?? "";
        if (!s.startsWith(PREFIX.command)) return;
        e.preventDefault(); e.stopPropagation();
        const name = s.slice(PREFIX.command.length);
        const list = custom.filter((x) => x !== name);
        const i = list.indexOf(n);
        list.splice(i < 0 ? list.length : i, 0, name);
        setCustom(list);
      });
      t.addEventListener("contextmenu", (e) => { e.preventDefault(); showMenu([{ title: "Remove from My Tools", action: () => setCustom(custom.filter((x) => x !== n)) }], { x: e.clientX, y: e.clientY }); });
      grid.append(t);
    }
  }
  async function shapeTiles(grid: HTMLElement, which: "Blocks" | "Components") {
    const key = `${app.info?.title ?? ""}|${app.info?.entities ?? 0}|${app.info?.dirty ?? false}`;
    if (!itemsCache || itemsFor !== key) { itemsCache = (await app.tryCall("palette.items")) ?? { blocks: [], components: [] }; itemsFor = key; }
    const list = which === "Blocks" ? itemsCache!.blocks ?? [] : itemsCache!.components ?? [];
    if (which === "Blocks" && !list.length) grid.append(h("div", { class: "tp-empty", text: "No blocks in this drawing. Create one with BLOCK or insert a drawing with INSERT." }));
    for (const it of list) {
      const size = it.size ? `${Math.round(it.size[0])}×${Math.round(it.size[1])}×${Math.round(it.size[2])}` : "";
      const tip = which === "Blocks" ? `Click, then click in the drawing to place ${it.name} (Space rotates 90°) · or drag onto the drawing`
        : `${it.category} · ${size} — click, then click in the drawing to place (Space rotates 90°), or drag onto the drawing`;
      const b = h("button", { class: "tp-shape" }, thumb(it.shapes ?? []), h("span", { class: "tp-title", text: it.name })) as HTMLButtonElement;
      help(b, tip);
      b.addEventListener("click", () => document.dispatchEvent(new CustomEvent("archi:placement", { detail: { item: it.item, title: it.name } })));
      draggable(b, it.item);
      grid.append(b);
    }
  }
  render();
}

/** Line thumbnail of a block / component (BlockThumb + ShapeTile canvas). */
function thumb(shapes: [number, number][][]): HTMLCanvasElement {
  const c = h("canvas", { class: "tp-thumb" }) as HTMLCanvasElement;
  const W = 76, H = 40, d = window.devicePixelRatio || 1;
  c.width = W * d; c.height = H * d; c.style.width = W + "px"; c.style.height = H + "px";
  const ctx = c.getContext("2d")!;
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const s of shapes) for (const p of s) { x0 = Math.min(x0, p[0]); y0 = Math.min(y0, p[1]); x1 = Math.max(x1, p[0]); y1 = Math.max(y1, p[1]); }
  if (!isFinite(x0)) return c;
  const k = Math.min((W - 6) / Math.max(x1 - x0, 1e-9), (H - 6) / Math.max(y1 - y0, 1e-9));
  const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
  ctx.setTransform(d, 0, 0, d, 0, 0);
  ctx.strokeStyle = getComputedStyle(document.body).getPropertyValue("--text") || "#E6E6E6";
  ctx.lineWidth = 1;
  ctx.beginPath();
  for (const s of shapes) {
    if (s.length < 2) continue;
    s.forEach((p, i) => { const x = W / 2 + (p[0] - cx) * k, y = H / 2 - (p[1] - cy) * k; if (i) ctx.lineTo(x, y); else ctx.moveTo(x, y); });
  }
  ctx.stroke();
  return c;
}

// The docked Tools panel is the tool palette (the Mac PanelTab.tools shows ToolPalettePanel).
const P = Panels.prototype as any;
const localPanel = P.localPanel;
P.localPanel = function (tab: string) {
  if (tab === "Tools") return renderToolPalette(this.app, this.body);
  return localPanel.call(this, tab);
};
