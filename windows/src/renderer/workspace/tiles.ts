// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Tiled model views (TiledViews.swift, TILEDVIEWS / VPORTS): the Split workspace shows 2, 3 or 4 tiles — plan, 3D,
// section or an elevation — each with its own zoom and pan, a tile menu (view kind and arrangement) in its top-right
// corner, and resizable dividers. Arrangement and kinds are remembered across launches. Section and elevation tiles
// paint the engine's hidden-line projection (view.projection) on white paper like ProjectionTileView.
import type { App } from "../app";
import { h, clear } from "../dom";
import { showMenu } from "../ui/menu";
import { decodeDrawList, paintItems, applyView, defaultParams, type Entry, type Item } from "../canvas/drawitems";

export const TILE_KINDS = ["Plan", "3D", "Section", "North", "South", "East", "West"] as const;
export type TileKind = (typeof TILE_KINDS)[number];
export const ARRANGEMENTS: [string, string, number][] = [["two", "Two: side by side", 2], ["twoStacked", "Two: stacked", 2], ["three", "Three: one left, two right", 3], ["four", "Four: equal", 4]];
const DEFAULT_KINDS: TileKind[] = ["Plan", "3D", "Section", "South"];
const AKEY = "archi.tiles.arrangement", KKEY = "archi.tiles.kinds";

export const tileState = {
  get arrangement(): string { try { const v = localStorage.getItem(AKEY); return ARRANGEMENTS.some((a) => a[0] === v) ? v! : "two"; } catch { return "two"; } },
  set arrangement(v: string) { try { localStorage.setItem(AKEY, v); } catch {} },
  get kinds(): TileKind[] {
    let raw: string[] = [];
    try { raw = JSON.parse(localStorage.getItem(KKEY) ?? "[]"); } catch {}
    const k = raw.filter((x): x is TileKind => (TILE_KINDS as readonly string[]).includes(x));
    while (k.length < 4) k.push(DEFAULT_KINDS[k.length]);
    return k.slice(0, 4);
  },
  set kinds(v: TileKind[]) { try { localStorage.setItem(KKEY, JSON.stringify(v.slice(0, 4))); } catch {} },
  setKind(k: TileKind, i: number) { const a = this.kinds; if (i >= 0 && i < 4) { a[i] = k; this.kinds = a; } },
  count(): number { return ARRANGEMENTS.find((a) => a[0] === this.arrangement)?.[2] ?? 2; },
};
/** Arrangement name of the TILEDVIEWS keyword (2, Stacked, 3, 4). */
export function arrangementFor(k: string) { return k === "2" ? "two" : k === "Stacked" ? "twoStacked" : k === "3" ? "three" : "four"; }
export function arrangementTitle(a = tileState.arrangement) { return ARRANGEMENTS.find((x) => x[0] === a)?.[1] ?? a; }

export interface TileHosts { plan: HTMLElement; view3d: HTMLElement; ensure3D(): void; changed(): void }

const fractions = new Map<string, number>();
/** Two panes with a draggable divider (HSplitView / VSplitView); `key` remembers the split for this session. */
function split(dir: "row" | "col", a: HTMLElement, b: HTMLElement, key: string): HTMLElement {
  const f = fractions.get(key) ?? 0.5;
  const box = h("div", { class: `ws-split ${dir}` });
  const pa = h("div", { class: "pane" }, a), pb = h("div", { class: "pane" }, b);
  pa.style.flex = `${f} 1 0`; pb.style.flex = `${1 - f} 1 0`;
  const sep = h("div", { class: "ws-divider" });
  sep.addEventListener("mousedown", (e) => {
    const r = box.getBoundingClientRect();
    const mv = (ev: MouseEvent) => {
      const x = dir === "row" ? (ev.clientX - r.left) / r.width : (ev.clientY - r.top) / r.height;
      const v = Math.min(0.85, Math.max(0.15, x));
      fractions.set(key, v);
      pa.style.flex = `${v} 1 0`; pb.style.flex = `${1 - v} 1 0`;
    };
    const up = () => { removeEventListener("mousemove", mv); removeEventListener("mouseup", up); };
    addEventListener("mousemove", mv); addEventListener("mouseup", up);
    e.preventDefault();
  });
  sep.addEventListener("dblclick", () => { fractions.delete(key); pa.style.flex = "0.5 1 0"; pb.style.flex = "0.5 1 0"; });
  box.append(pa, sep, pb);
  return box;
}

/** A 2D tile with its own zoom and pan: a projection (section / elevation) on paper, or a second plan view. The engine
 *  paints projections (hundreds of thousands of hidden-line fills in a real model) into a PNG for the tile's window;
 *  while panning and zooming the last image is moved and scaled, then repainted for the new window. */
class DrawTile {
  el: HTMLElement;
  private cv: HTMLCanvasElement;
  private entries: Entry[] = [];
  private bounds: number[] | null = null;
  private v = { cx: 0, cy: 0, scale: 0.02, w: 300, h: 200 };
  private fitted = false;
  private title = "";
  private loaded = -1;
  private img: { el: HTMLImageElement; rect: number[] } | null = null;
  private timer = 0;
  private seq = 0;

  constructor(private app: App, private kind: TileKind, private stamp: () => number) {
    this.cv = h("canvas") as HTMLCanvasElement;
    this.el = h("div", { class: "ws-drawtile" + (kind === "Plan" ? " plan" : "") }, this.cv);
    new ResizeObserver(() => { this.paint(); this.requestImage(); }).observe(this.el);
    this.cv.addEventListener("wheel", (e) => { e.preventDefault(); const r = this.cv.getBoundingClientRect(); this.zoom(Math.pow(1.2, -Math.sign(e.deltaY)), e.clientX - r.left, e.clientY - r.top); }, { passive: false });
    this.cv.addEventListener("mousedown", (e) => {
      let x0 = e.clientX, y0 = e.clientY;
      const mv = (ev: MouseEvent) => { this.v.cx -= (ev.clientX - x0) / this.v.scale; this.v.cy += (ev.clientY - y0) / this.v.scale; x0 = ev.clientX; y0 = ev.clientY; this.paint(); };
      const up = () => { removeEventListener("mousemove", mv); removeEventListener("mouseup", up); this.requestImage(); };
      addEventListener("mousemove", mv); addEventListener("mouseup", up);
      e.preventDefault();
    });
    this.cv.addEventListener("dblclick", () => { this.fitted = false; this.paint(); this.requestImage(); });
    void this.load();
  }
  private get paper() { return this.kind !== "Plan"; }
  private viewRect(): number[] { const hw = this.v.w / 2 / this.v.scale, hh = this.v.h / 2 / this.v.scale; return [this.v.cx - hw, this.v.cy - hh, this.v.cx + hw, this.v.cy + hh]; }
  async load() {
    const s = this.stamp();
    if (this.loaded === s) return;
    this.loaded = s;
    if (this.paper) { this.img = null; await this.fetchImage(true); return; }
    const r = await this.app.tryCall("view.drawList", {});
    this.entries = decodeDrawList(r ?? { items: [] });
    this.bounds = Array.isArray(r?.bounds) ? r.bounds : null;
    this.title = `${this.app.info?.currentLevel ?? ""} Plan`;
    this.paint();
  }
  private requestImage() {
    if (!this.paper) return;
    clearTimeout(this.timer);
    this.timer = window.setTimeout(() => void this.fetchImage(false), 180);
  }
  private async fetchImage(first: boolean) {
    const dpr = devicePixelRatio || 1;
    const w = this.el.clientWidth || 400, hh = this.el.clientHeight || 300;
    const seq = ++this.seq;
    const params: any = { view: this.kind, width: Math.round(w * dpr), height: Math.round(hh * dpr), dpr };
    if (!first && this.fitted) params.rect = this.viewRect();
    const r = await this.app.tryCall("view.projection", params);
    if (seq !== this.seq || !r) return;
    this.title = String(r.title ?? this.kind);
    this.bounds = Array.isArray(r.bounds) ? r.bounds : null;
    if (typeof r.png === "string" && Array.isArray(r.rect)) {
      const el = new Image();
      el.onload = () => {
        if (seq !== this.seq) return;
        this.img = { el, rect: r.rect };
        if (first || !this.fitted) { this.v.cx = (r.rect[0] + r.rect[2]) / 2; this.v.cy = (r.rect[1] + r.rect[3]) / 2; this.v.scale = w / Math.max(r.rect[2] - r.rect[0], 1e-9); this.fitted = true; }
        this.paint();
      };
      el.src = "data:image/png;base64," + r.png;
      return;
    }
    // Draw items (a small drawing or the fixture engine).
    this.entries = decodeDrawList(r);
    this.img = null;
    this.paint();
  }
  private fit() {
    const b = this.bounds;
    if (!b || this.v.w < 10 || this.v.h < 10) return;
    this.v.scale = Math.min((this.v.w * 0.9) / Math.max(b[2] - b[0], 1), (this.v.h * 0.9) / Math.max(b[3] - b[1], 1));
    this.v.cx = (b[0] + b[2]) / 2; this.v.cy = (b[1] + b[3]) / 2;
    this.fitted = true;
  }
  private zoom(f: number, px: number, py: number) {
    const wx = (px - this.v.w / 2) / this.v.scale + this.v.cx, wy = (this.v.h / 2 - py) / this.v.scale + this.v.cy;
    this.v.scale = Math.min(Math.max(this.v.scale * f, 1e-6), 1e3);
    this.v.cx = wx - (px - this.v.w / 2) / this.v.scale; this.v.cy = wy - (this.v.h / 2 - py) / this.v.scale;
    this.paint();
    this.requestImage();
  }
  paint() {
    const w = this.el.clientWidth, hh = this.el.clientHeight, dpr = devicePixelRatio || 1;
    if (!w || !hh) return;
    this.v.w = w; this.v.h = hh;
    if (this.cv.width !== Math.round(w * dpr) || this.cv.height !== Math.round(hh * dpr)) { this.cv.width = Math.round(w * dpr); this.cv.height = Math.round(hh * dpr); this.cv.style.width = w + "px"; this.cv.style.height = hh + "px"; }
    if (!this.fitted && !this.img) this.fit();
    const ctx = this.cv.getContext("2d");
    if (!ctx) return;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = this.paper ? "#FFFFFF" : getComputedStyle(document.documentElement).getPropertyValue("--canvas").trim() || "#1E1F22";
    ctx.fillRect(0, 0, this.cv.width, this.cv.height);
    if (this.img) {
      const r = this.img.rect;
      const x0 = (r[0] - this.v.cx) * this.v.scale + w / 2, y0 = hh / 2 - (r[3] - this.v.cy) * this.v.scale;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.imageSmoothingQuality = "high";
      ctx.drawImage(this.img.el, x0, y0, (r[2] - r[0]) * this.v.scale, (r[3] - r[1]) * this.v.scale);
    } else {
      applyView(ctx, this.v, dpr);
      const items: Item[] = this.entries.flatMap((e) => e.items);
      paintItems(ctx, this.paper ? items.map(onPaper) : items, this.v, { ...defaultParams, lwScale: 2.2, minWidth: 0.5 });
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.font = "600 10px var(--ui, sans-serif)";
    ctx.fillStyle = this.paper ? "#555" : "#9A9BA1";
    ctx.fillText(this.title, 8, hh - 8);
  }
}
/** Plot colours on white paper (PlotRenderer paper: white and very light colours print black). */
function onPaper(it: Item): Item {
  const c = (it as any).color as string | undefined;
  if (!c) return it;
  let rgb: number[] | null = null;
  const hex = /^#([0-9a-f]{6})/i.exec(c);
  if (hex) rgb = [0, 2, 4].map((i) => parseInt(hex[1].slice(i, i + 2), 16));
  const m = /^rgba?\(([^)]+)\)/i.exec(c);
  if (m) rgb = m[1].split(",").slice(0, 3).map((x) => Number(x));
  if (!rgb || rgb.some((x) => !isFinite(x))) return it;
  return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2] > 200 ? ({ ...it, color: "#000000" } as Item) : it;
}

export class TiledViews {
  private stamp = 0;
  private tiles: DrawTile[] = [];
  constructor(private app: App, private hosts: TileHosts) {
    app.on(["drawing", "doc"], () => { this.stamp++; if (this.tiles.length) for (const t of this.tiles) void t.load(); });
  }
  /** Builds the tiles into the workspace (Split mode). */
  render(into: HTMLElement) {
    this.tiles = [];
    const n = tileState.count();
    const kinds = tileState.kinds;
    const used = new Set<string>();
    const tile = (i: number): HTMLElement => {
      const k = kinds[i];
      let content: HTMLElement;
      if (k === "Plan" && !used.has("Plan")) { used.add("Plan"); content = this.hosts.plan; }
      else if (k === "3D" && !used.has("3D")) { used.add("3D"); this.hosts.ensure3D(); content = this.hosts.view3d; }
      else if (k === "3D") content = h("div", { class: "ws-tile-note", text: "The 3D view is shown in another tile." });
      else { const t = new DrawTile(this.app, k, () => this.stamp); this.tiles.push(t); content = t.el; }
      const menu = h("button", { class: "ws-tilemenu", text: k });
      menu.title = "View shown in this tile · tile arrangement";
      menu.addEventListener("click", () => showMenu([
        ...TILE_KINDS.map((t) => ({ title: t, checked: t === k, action: () => { tileState.setKind(t, i); this.hosts.changed(); } })),
        { separator: true } as any,
        ...ARRANGEMENTS.map(([a, title]) => ({ title, checked: a === tileState.arrangement, action: () => { tileState.arrangement = a; this.hosts.changed(); } })),
      ], menu));
      return h("div", { class: "ws-tile", "data-kind": k }, content, menu);
    };
    clear(into);
    let root: HTMLElement;
    const a = tileState.arrangement;
    if (a === "twoStacked") root = split("col", tile(0), tile(1), "s");
    else if (a === "three") root = split("row", tile(0), split("col", tile(1), tile(2), "3r"), "3");
    else if (a === "four") root = split("col", split("row", tile(0), tile(1), "4t"), split("row", tile(2), tile(3), "4b"), "4");
    else root = split("row", tile(0), tile(1), "2");
    void n;
    root.classList.add("ws-tiles");
    into.append(root);
  }
}
