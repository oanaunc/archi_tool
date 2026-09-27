// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The 2D drafting canvas — PlanCanvasView (ArchiApp/CanvasView.swift) and, for sheets, SheetCanvasNSView (SheetView.swift):
// paints the engine's DrawList with the Mac colours, grid and axes, the UCS icon, twisted (VIEWTWIST) views, selection
// highlight, grips and door / window flip arrows; the overlay draws the hover highlight, the command preview, the
// dynamic-UCS axes, grip-drag and palette-placement previews in the accent colour, the rubber band, window / crossing
// rectangles and freehand lassos (Alt+drag), hot and hovered grips, object snap tracking vectors with the tracking
// readout, snap markers, the crosshair with its pick box, and the dynamic-input tooltip with Length / Angle fields (Tab).
// Input follows the Mac canvas: click / Shift-click selection with cycling through overlapping objects, click-click and
// drag windows, grips (drag or click-click, Space / Enter cycles Stretch → Move → Rotate → Scale → Mirror, C copy,
// typed values and points, multi-functional grip menus on right-click), double-click editing, Tab selects joined walls,
// arrow keys nudge, right-click = Enter during commands / shortcut menu / right-drag marking menu, Shift+right-click =
// snap overrides, temporary dimensions on selected BIM elements, palette click-to-place and drag-and-drop of palette
// items and files. Navigation uses the Windows conventions: wheel = zoom about the cursor, Ctrl+wheel / touchpad pinch =
// zoom, touchpad two-finger scroll and Shift+wheel = pan, middle-drag or Space+drag = pan, double middle-click = extents.
import { prefs } from "../prefs";
import type { App } from "../app";
import { snapPoint, type Grip, type SnapInfo } from "../../shared/protocol";
import { decodeDrawList, decodeItem, paintItems, applyView, Entry, Item, View, Params, defaultParams, pick, setImageLoadedCallback, setImageUrlResolver } from "./drawitems";
import { showMenu, closeMenus, type MenuItem } from "../ui/menu";
import { shortcutItems, SNAP_OVERRIDES, RadialMenuView, radialItems, radialContext, radialSector, radialTooltip, radialPrefs, type ShortcutItem } from "./canvas-menus";
import { InPlaceTextEditor, editTextAlert } from "./text-editor";
import { PREFIX, DROP_TYPE } from "./tool-palette";
import { installFakeCanvas } from "./fake-canvas";
import "./canvas.css";

const ACCENT = "#F5C518";
const MM_PER_UNIT: Record<string, number> = { millimeters: 1, centimeters: 10, meters: 1000, inches: 25.4, feet: 304.8 };
type V2 = [number, number];
type GripMode = "stretch" | "move" | "rotate" | "scale" | "mirror";
const GRIP_MODES: GripMode[] = ["stretch", "move", "rotate", "scale", "mirror"];
const MODE_KEYWORDS: Record<string, GripMode> = { ST: "stretch", STRETCH: "stretch", MO: "move", MOVE: "move", RO: "rotate", ROTATE: "rotate", SC: "scale", SCALE: "scale", MI: "mirror", MIRROR: "mirror" };
const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
const fmt = (v: number, d: number) => { const s = v.toFixed(d); return s.includes(".") ? s.replace(/\.?0+$/, "") : s; };

type WindowSel = { start: V2; current: V2; moved: boolean; purpose: "select" | "request" | "zoom"; shift: boolean; lasso: V2[] | null };
interface HotGrip {
  grip: Grip; origin: V2; startView: V2; moved: boolean; dragging: boolean;
  /** Quarter turns added with Space while dragging (MOD-029). */ turns: number;
  /** Grip mode (SEL-034) and Copy. */ mode: GripMode; copy: boolean;
  /** Multi-functional grip option (SEL-035). */ action: string | null; actionTitle: string | null;
  items: Item[]; point: V2 | null; snap: SnapInfo | null; reference?: number;
}
interface CanvasState {
  ucs: { origin: V2; angle: number; world: boolean }; ucsIcon: { on: boolean; atOrigin: boolean }; twist: number;
  isometric: boolean; isoPlane: number; ducs: boolean; doubleClickEditing: boolean; grips: boolean; selectionPreview: number;
  lastCommand: string | null; canUndo: boolean; canRedo: boolean; undoLabel: string | null; redoLabel: string | null; maximizedViewport?: [number, number];
}
interface Flip { id: number; kind: string; point: V2; direction: V2 }
interface TempDim { id: number; index: number; from: V2; to: V2; value: number; text: string }
interface SheetVP { index: number; rect: number[]; scale: number; ratioText?: string; title?: string; view?: string; locked?: boolean; clip?: V2[] }
interface Tracking { points: V2[]; lines: { from: V2; to: V2 }[] }
interface DynFields { length?: number; angle?: number; x: number; y: number; relative: boolean }

export class PlanCanvas {
  el: HTMLElement;
  private content: HTMLCanvasElement;
  private overlay: HTMLCanvasElement;
  private v: View = { cx: 12000, cy: 7000, scale: 0.04, w: 800, h: 600, twist: 0 };
  private dpr = 1;
  private entries: Entry[] = [];
  private byId = new Map<string, Entry>();
  private grips: Grip[] = [];
  private flips: Flip[] = [];
  private tempDims: TempDim[] = [];
  private mouse: V2 | null = null;
  private world: V2 = [0, 0];
  private hover: Entry | null = null;
  private hoverGrip: Grip | null = null;
  private hot: HotGrip | null = null;
  private preview: Item[] = [];
  private snap: SnapInfo | null = null;
  private tracking: Tracking | null = null;
  private dyn: DynFields | null = null;
  private ducs: { from: V2; to: V2; color: string }[] = [];
  private win: WindowSel | null = null;
  private panLast: V2 | null = null;
  private spaceDown = false;
  private spacePanned = false;
  private needsInitialZoom = true;
  private zoomWindowPending = false;
  private contentDirty = true;
  private overlayDirty = true;
  private cursorBusy = false;
  private cursorPending = false;
  private lastMiddle = 0;
  private requestedScale = 0;
  private drawSeq = 0;
  private gridSpacing = 0;
  private paper: { w: number; h: number; name: string } | null = null;
  private lastLayout = "";
  private viewports: SheetVP[] = [];
  private sheetGrid = 0;
  private selectedViewport: number | null = null;
  private vpDrag: { index: number; start: V2; origin: V2; preview: V2 | null; pan: boolean } | null = null;
  private state: CanvasState = { ucs: { origin: [0, 0], angle: 0, world: true }, ucsIcon: { on: true, atOrigin: true }, twist: 0, isometric: false, isoPlane: 0, ducs: false,
    doubleClickEditing: true, grips: true, selectionPreview: 3, lastCommand: null, canUndo: false, canRedo: false, undoLabel: null, redoLabel: null };
  /** Overlapping objects under the last pick: clicking again at the same spot selects the next one (SEL-018). */
  private cycle: { point: V2; ids: string[]; index: number } | null = null;
  /** Click-to-place from the tool palette (MOD-029). */
  private placement: { item: string; title: string; turns: number; items: Item[] } | null = null;
  private radial: { origin: V2; client: V2; view: RadialMenuView | null; context: string | null } | null = null;
  /** Dynamic-input fields being typed (Tab moves between Length and Angle, or X and Y). */
  private dynInput: { field: 0 | 1; values: [string, string] } | null = null;
  private zoomHistory: [number, number, number][] = [];
  private userZoomed = false;
  private hint = "";
  private swallowSpaceUp = false;

  constructor(private app: App, readonly interactive = true) {
    this.content = document.createElement("canvas");
    this.overlay = document.createElement("canvas");
    this.content.className = "plan"; this.overlay.className = "plan";
    this.overlay.tabIndex = 0;
    this.overlay.setAttribute("aria-label", "Drawing canvas");
    this.el = document.createElement("div");
    this.el.style.cssText = "position:absolute;inset:0";
    this.el.append(this.content, this.overlay);
    new ResizeObserver(() => this.resize()).observe(this.el);
    addEventListener("archi:dpr", () => this.resize()); // window moved to a monitor with another scale factor
    setImageLoadedCallback(() => { this.contentDirty = true; this.schedule(); });
    if (app.engine.native) setImageUrlResolver((p) => app.engine.native!.fileUrl(p));
    if ((app.engine as any).kind === "fixtures") installFakeCanvas(app.engine as any);
    app.on(["drawing", "layers"], () => { this.loadDrawList(); this.loadState(); });
    app.on("selection", () => { this.cycleCheck(); this.loadGrips(); });
    app.on("sysvars", () => { this.contentDirty = true; this.schedule(); });
    app.on("prompt", () => {
      if (!app.prompt.active) { this.preview = []; this.snap = null; this.tracking = null; this.dyn = null; this.ducs = []; this.dynInput = null; }
      else this.preview = (app.prompt.preview ?? []).map(decodeItem).filter(Boolean) as Item[];
      this.loadGrips();
      this.overlayDirty = true; this.schedule();
    });
    app.on("ui", () => { this.loadDrawList(); });
    app.on("live", () => { this.overlayDirty = true; this.schedule(); });
    this.bind();
    this.hookApp();
    document.addEventListener("archi:placement", (e: any) => this.startPlacement(String(e.detail?.item ?? ""), String(e.detail?.title ?? "")));
    (window as any).archiCanvas = this; // tests and the script console
  }

  // ---- data ----
  async loadDrawList() {
    const app = this.app;
    const seq = ++this.drawSeq;
    const ext = app.info?.extents;
    const pad = ext ? Math.max(ext[2] - ext[0], ext[3] - ext[1]) : 1e6;
    const rect = ext ? [ext[0] - pad, ext[1] - pad, ext[2] + pad, ext[3] + pad] : [-1e7, -1e7, 1e7, 1e7];
    const params: any = { rect, pixelsPerUnit: this.v.scale, level: app.info?.currentLevel };
    if (app.mode === "Sheet" && app.activeLayout > 0) params.layout = app.info?.layouts[app.activeLayout - 1];
    this.requestedScale = this.v.scale;
    const res = await app.tryCall("view.drawList", params);
    if (seq !== this.drawSeq) return;
    this.entries = res ? decodeDrawList(res) : [];
    if (res?.grid?.spacing) this.gridSpacing = Number(res.grid.spacing);
    const paper = res?.paper && typeof res.paper.width === "number" ? { w: Number(res.paper.width), h: Number(res.paper.height), name: String(res.paper.name ?? "") } : null;
    const layoutKey = params.layout ?? "";
    this.paper = paper;
    this.overlay.style.cursor = paper ? "default" : "";
    this.viewports = Array.isArray(res?.viewports) ? res.viewports.filter((v: any) => Array.isArray(v.rect)) : [];
    if (paper) {
      const sv = await app.tryCall("sheet.viewports", { layout: params.layout });
      if (seq !== this.drawSeq) return;
      if (sv?.viewports) { this.viewports = sv.viewports; this.sheetGrid = Number(sv.grid ?? 0); }
    }
    if (layoutKey !== this.lastLayout) { this.lastLayout = layoutKey; this.selectedViewport = null; if (paper) this.fitPaper(); else if (this.entries.length) this.zoomExtents(false); }
    this.byId = new Map(this.entries.filter((e) => e.id).map((e) => [e.id!, e]));
    if (this.needsInitialZoom && this.entries.length && !params.layout) { this.needsInitialZoom = false; this.zoomExtents(false); }
    this.contentDirty = true; this.schedule();
  }
  async loadGrips() {
    const app = this.app;
    const ids = app.selection.ids;
    if (!ids.length || !app.isIdle) { this.grips = []; this.flips = []; this.tempDims = []; this.contentDirty = true; this.schedule(); return; }
    const [g, f, t] = await Promise.all([
      ids.length <= 300 ? app.tryCall("grips.get") : Promise.resolve([]),
      ids.length <= 20 ? app.tryCall("flips.get", { pixelsPerUnit: this.v.scale }) : Promise.resolve([]),
      ids.length === 1 ? app.tryCall("tempdims.get") : Promise.resolve([]),
    ]);
    this.grips = Array.isArray(g) ? g : (g as any)?.grips ?? [];
    this.flips = Array.isArray(f) ? f : [];
    this.tempDims = Array.isArray(t) ? t : [];
    this.contentDirty = true; this.schedule();
  }
  async loadState() {
    const st = await this.app.tryCall("canvas.state");
    if (!st) return;
    const twistChanged = (Number(st.twist) || 0) !== this.state.twist;
    this.state = { ...this.state, ...st, twist: Number(st.twist) || 0 };
    if (twistChanged) { this.v.twist = (this.state.twist * Math.PI) / 180; this.viewChanged(); }
    this.contentDirty = true; this.schedule();
  }

  // ---- view ----
  private resize() {
    const r = this.el.getBoundingClientRect();
    this.dpr = window.devicePixelRatio || 1;
    const old = [this.v.w, this.v.h];
    this.v.w = Math.max(1, r.width); this.v.h = Math.max(1, r.height);
    for (const c of [this.content, this.overlay]) { c.width = Math.round(this.v.w * this.dpr); c.height = Math.round(this.v.h * this.dpr); }
    this.contentDirty = this.overlayDirty = true;
    // Split divider / window resize: a view the user never zoomed stays fitted to the drawing.
    if (!this.userZoomed && !this.paper && (Math.abs(old[0] - this.v.w) > 1 || Math.abs(old[1] - this.v.h) > 1) && this.entries.length) this.zoomExtents(false);
    this.paintNow();
  }
  private get tw() { return this.v.twist ?? 0; }
  toWorld(x: number, y: number): V2 {
    const rx = x - this.v.w / 2, ry = this.v.h / 2 - y, c = Math.cos(this.tw), s = Math.sin(this.tw);
    return [(rx * c + ry * s) / this.v.scale + this.v.cx, (-rx * s + ry * c) / this.v.scale + this.v.cy];
  }
  toView(p: V2): V2 {
    const ox = (p[0] - this.v.cx) * this.v.scale, oy = (p[1] - this.v.cy) * this.v.scale, c = Math.cos(this.tw), s = Math.sin(this.tw);
    return [ox * c - oy * s + this.v.w / 2, this.v.h / 2 - (ox * s + oy * c)];
  }
  /** Screen direction (y down) of a world direction. */
  private screenDir(d: V2): V2 { const c = Math.cos(this.tw), s = Math.sin(this.tw); return [d[0] * c - d[1] * s, -(d[0] * s + d[1] * c)]; }
  private visibleWorld(): [number, number, number, number] {
    const pts = [this.toWorld(0, 0), this.toWorld(this.v.w, 0), this.toWorld(0, this.v.h), this.toWorld(this.v.w, this.v.h)];
    return [Math.min(...pts.map((p) => p[0])), Math.min(...pts.map((p) => p[1])), Math.max(...pts.map((p) => p[0])), Math.max(...pts.map((p) => p[1]))];
  }
  zoomExtents(record = true) {
    if (this.paper) { this.fitPaper(); return; }
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const e of this.entries) { if (!isFinite(e.bounds[0])) continue; x0 = Math.min(x0, e.bounds[0]); y0 = Math.min(y0, e.bounds[1]); x1 = Math.max(x1, e.bounds[2]); y1 = Math.max(y1, e.bounds[3]); }
    if (!isFinite(x0)) { const ex = this.app.info?.extents; if (ex) [x0, y0, x1, y1] = ex; else return; }
    this.zoomTo([x0, y0, x1, y1], 0.06, record);
    this.userZoomed = false;
  }
  /** Fits the rectangle (a twisted view fits the rotated rectangle's screen bounds), as PlanCanvasView.zoom(toRect:). */
  zoomTo(b: [number, number, number, number], margin = 0.02, record = true) {
    if (record) { this.zoomHistory.push([this.v.cx, this.v.cy, this.v.scale]); if (this.zoomHistory.length > 50) this.zoomHistory.shift(); }
    const c = Math.abs(Math.cos(this.tw)), s = Math.abs(Math.sin(this.tw));
    const bw = Math.max(b[2] - b[0], 1e-6), bh = Math.max(b[3] - b[1], 1e-6);
    const w = Math.max(bw * c + bh * s, 1e-6), hh = Math.max(bw * s + bh * c, 1e-6);
    this.v.scale = Math.min((this.v.w * (1 - 2 * margin)) / w, (this.v.h * (1 - 2 * margin)) / hh);
    this.v.cx = (b[0] + b[2]) / 2; this.v.cy = (b[1] + b[3]) / 2;
    this.userZoomed = true;
    this.viewChanged();
  }
  zoomPrevious() { const z = this.zoomHistory.pop(); if (!z) { this.app.print("No previous view."); return; } [this.v.cx, this.v.cy, this.v.scale] = z; this.viewChanged(); }
  private fitPaper() {
    if (!this.paper) return;
    // SheetCanvasNSView.fit: the paper with a 30 pt margin.
    const s = Math.max(0.05, Math.min((this.v.w - 60) / this.paper.w, (this.v.h - 60) / this.paper.h));
    this.v.scale = s; this.v.cx = this.paper.w / 2; this.v.cy = this.paper.h / 2;
    this.viewChanged();
  }
  zoomBy(f: number, at?: V2) {
    const p = at ?? [this.v.w / 2, this.v.h / 2];
    const before = this.toWorld(p[0], p[1]);
    this.v.scale = Math.min(1e5, Math.max(1e-7, this.v.scale * f));
    const after = this.toWorld(p[0], p[1]);
    this.v.cx += before[0] - after[0]; this.v.cy += before[1] - after[1];
    this.userZoomed = true;
    this.viewChanged();
  }
  /** Pans by a screen offset (y down). */
  panView(dx: number, dy: number) {
    const c = Math.cos(this.tw), s = Math.sin(this.tw), ry = -dy;
    this.v.cx -= (dx * c + ry * s) / this.v.scale; this.v.cy -= (-dx * s + ry * c) / this.v.scale;
    this.userZoomed = true;
    this.viewChanged();
  }
  zoomWindow() { this.zoomWindowPending = true; this.focus(); }
  private viewTimer = 0;
  private viewChanged() {
    const units = this.app.info?.units ?? "millimeters";
    this.app.live.zoomPercent = (this.v.scale / ((72 / 25.4) * (this.paper ? 1 : MM_PER_UNIT[units] ?? 1))) * 100;
    this.app.emit("live");
    this.contentDirty = this.overlayDirty = true; this.schedule();
    if (this.requestedScale && (this.v.scale / this.requestedScale > 4 || this.requestedScale / this.v.scale > 4)) { clearTimeout((this as any)._rq); (this as any)._rq = setTimeout(() => this.loadDrawList(), 250); }
    clearTimeout(this.viewTimer);
    this.viewTimer = window.setTimeout(() => {
      if (this.paper) return;
      const b = this.visibleWorld();
      void this.app.tryCall("canvas.view", { center: [this.v.cx, this.v.cy], scale: this.v.scale, rect: b, radialMenu: radialPrefs.enabled });
    }, 200);
  }
  private resetCursor() { this.overlay.style.cursor = this.paper ? "default" : ""; }
  focus() { if (!InPlaceTextEditor.current) this.overlay.focus({ preventScroll: true }); }
  refresh() { this.contentDirty = this.overlayDirty = true; this.schedule(); }

  private frame = 0;
  private schedule() { if (!this.frame) this.frame = requestAnimationFrame(() => { this.frame = 0; this.paintNow(); }); }
  paintNow() {
    if (this.contentDirty) { this.paintContent(); this.contentDirty = false; }
    this.paintOverlay(); this.overlayDirty = false;
  }
  private params(): Params { return { ...defaultParams, lineweights: this.app.sysvarOn("LWDISPLAY"), minWidth: 1 / (window.devicePixelRatio || 1) }; }

  // ---- content ----
  private paintContent() {
    const ctx = this.content.getContext("2d")!;
    const { w, h } = this.v, d = this.dpr;
    ctx.setTransform(d, 0, 0, d, 0, 0);
    ctx.fillStyle = prefs.canvasColor; ctx.fillRect(0, 0, w, h);
    if (this.paper) { this.paintSheet(ctx); return; }
    if (this.app.sysvarOn("GRIDMODE")) this.paintGrid(ctx); else this.paintAxes(ctx);
    const [vx0, vy0, vx1, vy1] = this.visibleWorld();
    const vis = this.entries.filter((e) => !(e.bounds[2] < vx0 || e.bounds[0] > vx1 || e.bounds[3] < vy0 || e.bounds[1] > vy1));
    applyView(ctx, this.v, d);
    const prm = this.params();
    const items: Item[] = [];
    for (const e of vis) for (const it of e.items) items.push(it);
    paintItems(ctx, items, this.v, prm);
    const sel = this.app.selection.ids.map((id) => this.byId.get(id)).filter(Boolean) as Entry[];
    if (sel.length) {
      if (sel.length < 800) { ctx.shadowColor = "rgba(245,197,24,0.7)"; ctx.shadowBlur = 5 * d; }
      paintItems(ctx, sel.flatMap((e) => e.items), this.v, prm, { colorOverride: ACCENT, extraWidth: 1, dashed: true, fillAlpha: 0.1 });
      ctx.shadowBlur = 0; ctx.shadowColor = "transparent";
    }
    ctx.setTransform(d, 0, 0, d, 0, 0);
    this.paintGrips(ctx);
    this.paintUCS(ctx);
  }
  private paintAxes(ctx: CanvasRenderingContext2D) {
    const o = this.toView([0, 0]);
    ctx.lineWidth = 1;
    if (this.tw) {
      // Axes through the origin along the twisted directions.
      const far = Math.max(this.v.w, this.v.h) * 2, ux = this.screenDir([1, 0]), uy = this.screenDir([0, 1]);
      ctx.strokeStyle = "rgba(217,77,77,0.28)"; ctx.beginPath(); ctx.moveTo(o[0] - ux[0] * far, o[1] - ux[1] * far); ctx.lineTo(o[0] + ux[0] * far, o[1] + ux[1] * far); ctx.stroke();
      ctx.strokeStyle = "rgba(77,204,102,0.28)"; ctx.beginPath(); ctx.moveTo(o[0] - uy[0] * far, o[1] - uy[1] * far); ctx.lineTo(o[0] + uy[0] * far, o[1] + uy[1] * far); ctx.stroke();
      return;
    }
    if (o[1] >= 0 && o[1] <= this.v.h) { ctx.strokeStyle = "rgba(217,77,77,0.28)"; ctx.beginPath(); ctx.moveTo(0, Math.round(o[1]) + 0.5); ctx.lineTo(this.v.w, Math.round(o[1]) + 0.5); ctx.stroke(); }
    if (o[0] >= 0 && o[0] <= this.v.w) { ctx.strokeStyle = "rgba(77,204,102,0.28)"; ctx.beginPath(); ctx.moveTo(Math.round(o[0]) + 0.5, 0); ctx.lineTo(Math.round(o[0]) + 0.5, this.v.h); ctx.stroke(); }
  }
  private paintGrid(ctx: CanvasRenderingContext2D) {
    const base = Math.max(this.gridSpacing || Number(this.app.sysvars.GRIDUNIT ?? 0) || (this.app.info?.units === "inches" ? 12 : 100), 1e-9);
    const s = this.v.scale;
    let minor = base;
    while (minor * s > 120) minor /= 10;
    const steps = [2, 2.5, 2]; let k = 0;
    while (minor * s < 10) { minor *= steps[k % 3]; k++; }
    const major = minor * 5;
    const [x0w, y0w, x1w, y1w] = this.visibleWorld();
    const i0 = Math.floor(x0w / minor), i1 = Math.ceil(x1w / minor), j0 = Math.floor(y0w / minor), j1 = Math.ceil(y1w / minor);
    if (i1 - i0 > 2000 || j1 - j0 > 2000) return;
    const mn = new Path2D(), mj = new Path2D();
    const isMajor = (w: number) => Math.abs(w / major - Math.round(w / major)) < 1e-6;
    if (this.tw) {
      // Twisted view: grid lines are world lines drawn through the view transform.
      for (let i = i0; i <= i1; i++) { const wx = i * minor, a = this.toView([wx, y0w]), b = this.toView([wx, y1w]), p = isMajor(wx) ? mj : mn; p.moveTo(a[0], a[1]); p.lineTo(b[0], b[1]); }
      for (let j = j0; j <= j1; j++) { const wy = j * minor, a = this.toView([x0w, wy]), b = this.toView([x1w, wy]), p = isMajor(wy) ? mj : mn; p.moveTo(a[0], a[1]); p.lineTo(b[0], b[1]); }
    } else {
      for (let i = i0; i <= i1; i++) {
        const wx = i * minor, x = Math.round((wx - this.v.cx) * s + this.v.w / 2) + 0.5;
        (isMajor(wx) ? mj : mn).moveTo(x, 0); (isMajor(wx) ? mj : mn).lineTo(x, this.v.h);
      }
      for (let j = j0; j <= j1; j++) {
        const wy = j * minor, y = Math.round(this.v.h / 2 - (wy - this.v.cy) * s) + 0.5;
        (isMajor(wy) ? mj : mn).moveTo(0, y); (isMajor(wy) ? mj : mn).lineTo(this.v.w, y);
      }
    }
    ctx.lineWidth = 1;
    ctx.strokeStyle = "rgba(255,255,255,0.035)"; ctx.stroke(mn);
    ctx.strokeStyle = "rgba(255,255,255,0.075)"; ctx.stroke(mj);
    this.paintAxes(ctx);
  }
  /** UCS icon (UCSICON ORigin): at the UCS origin when it is on screen, else in the lower-left corner, rotated to the UCS. */
  private paintUCS(ctx: CanvasRenderingContext2D) {
    const st = this.state;
    if (!st.ucsIcon.on) return;
    const len = 34;
    let o: V2 = [26, this.v.h - 26];
    const at = this.toView(st.ucs.origin);
    if (!st.ucs.world && st.ucsIcon.atOrigin && at[0] >= 40 && at[0] <= this.v.w - 40 && at[1] >= 40 && at[1] <= this.v.h - 40) o = at;
    const a = st.ucs.angle + this.tw;
    const ux: V2 = [Math.cos(a), -Math.sin(a)], uy: V2 = [-Math.sin(a), -Math.cos(a)];
    const pt = (d: V2, k: number): V2 => [o[0] + d[0] * k, o[1] + d[1] * k];
    const arrow = (d: V2, col: string) => {
      ctx.strokeStyle = col; ctx.fillStyle = col; ctx.lineWidth = 1.5;
      const tip = pt(d, len), back = pt(d, len - 6), n: V2 = [-d[1], d[0]];
      ctx.beginPath(); ctx.moveTo(o[0], o[1]); ctx.lineTo(tip[0], tip[1]); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(tip[0], tip[1]); ctx.lineTo(back[0] + n[0] * 3, back[1] + n[1] * 3); ctx.lineTo(back[0] - n[0] * 3, back[1] - n[1] * 3); ctx.closePath(); ctx.fill();
    };
    arrow(ux, "rgba(230,89,89,0.9)"); arrow(uy, "rgba(89,217,115,0.9)");
    ctx.strokeStyle = "rgba(217,217,217,0.9)"; ctx.lineWidth = 1;
    if (st.ucs.world) ctx.strokeRect(o[0] - 3, o[1] - 3, 6, 6); else { ctx.beginPath(); ctx.arc(o[0], o[1], 2.5, 0, Math.PI * 2); ctx.stroke(); }
    ctx.fillStyle = "rgba(217,217,217,0.9)"; ctx.font = "600 9px " + getComputedStyle(document.body).getPropertyValue("--ui");
    const xl = pt(ux, len + 8), yl = pt(uy, len + 8);
    ctx.textBaseline = "middle"; ctx.fillText("X", xl[0] - 3, xl[1]); ctx.fillText("Y", yl[0] - 3, yl[1]);
    if (st.ucs.world) ctx.fillText("W", o[0] + 6, o[1] - 8);
    ctx.textBaseline = "alphabetic";
  }
  private paintGrips(ctx: CanvasRenderingContext2D) {
    if (!this.app.isIdle) return;
    // Flip arrows: a double arrow across the swing side (facing) and along the wall (hand).
    ctx.fillStyle = ACCENT;
    for (const f of this.flips) {
      const v = this.toView(f.point), d0 = this.screenDir(f.direction), l = Math.hypot(d0[0], d0[1]) || 1;
      const d: V2 = [d0[0] / l, d0[1] / l], n: V2 = [-d[1], d[0]];
      for (const sg of [1, -1]) {
        const tip: V2 = [v[0] + d[0] * 7 * sg, v[1] + d[1] * 7 * sg], b: V2 = [v[0] + d[0] * 1.5 * sg, v[1] + d[1] * 1.5 * sg];
        ctx.beginPath(); ctx.moveTo(tip[0], tip[1]); ctx.lineTo(b[0] + n[0] * 4.5, b[1] + n[1] * 4.5); ctx.lineTo(b[0] - n[0] * 4.5, b[1] - n[1] * 4.5); ctx.closePath(); ctx.fill();
      }
    }
    const sz = 7;
    ctx.lineWidth = 1;
    for (const g of this.grips) {
      const [x, y] = this.toView([g.x, g.y]);
      if (x < -10 || y < -10 || x > this.v.w + 10 || y > this.v.h + 10) continue;
      const r = [Math.round(x - sz / 2) + 0.5, Math.round(y - sz / 2) + 0.5];
      ctx.fillStyle = "rgb(61,122,255)"; ctx.fillRect(r[0], r[1], sz, sz);
      ctx.strokeStyle = "rgba(230,240,255,0.9)"; ctx.strokeRect(r[0], r[1], sz, sz);
    }
  }
  /** Temporary dimensions of the selected BIM element (CMD-035): click the value to type a new distance. */
  private tempDimBoxes: { td: TempDim; box: [number, number, number, number] }[] = [];
  private paintTempDims(ctx: CanvasRenderingContext2D) {
    this.tempDimBoxes = [];
    if (!this.app.isIdle || this.hot) return;
    ctx.font = `10.5px ${getComputedStyle(document.body).getPropertyValue("--mono")}`;
    for (const td of this.tempDims) {
      const a = this.toView(td.from), b = this.toView(td.to), len = Math.hypot(b[0] - a[0], b[1] - a[1]);
      if (len < 4) continue;
      const n: V2 = [-(b[1] - a[1]) / len, (b[0] - a[0]) / len];
      ctx.strokeStyle = "rgba(110,170,255,0.95)"; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]);
      for (const p of [a, b]) { ctx.moveTo(p[0] - n[0] * 5, p[1] - n[1] * 5); ctx.lineTo(p[0] + n[0] * 5, p[1] + n[1] * 5); }
      ctx.stroke();
      const m: V2 = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
      const tw = ctx.measureText(td.text).width + 8, th = 15;
      const box: [number, number, number, number] = [m[0] - tw / 2, m[1] - th / 2, tw, th];
      ctx.fillStyle = "rgba(30,31,34,0.92)"; ctx.fillRect(box[0], box[1], box[2], box[3]);
      ctx.strokeStyle = "rgba(110,170,255,0.9)"; ctx.strokeRect(box[0] + 0.5, box[1] + 0.5, box[2] - 1, box[3] - 1);
      ctx.fillStyle = "#CFE2FF"; ctx.textBaseline = "middle"; ctx.fillText(td.text, box[0] + 4, m[1] + 0.5); ctx.textBaseline = "alphabetic";
      this.tempDimBoxes.push({ td, box });
    }
  }

  // ---- sheets (SheetCanvasNSView) ----
  private paintSheet(ctx: CanvasRenderingContext2D) {
    const p = this.paper!, d = this.dpr, { w, h } = this.v;
    ctx.fillStyle = "rgb(41,42,46)"; ctx.fillRect(0, 0, w, h);
    const a = this.toView([0, p.h]), b = this.toView([p.w, 0]);
    ctx.save();
    ctx.shadowColor = "rgba(0,0,0,0.6)"; ctx.shadowBlur = 18; ctx.shadowOffsetY = 5;
    ctx.fillStyle = "#FFFFFF"; ctx.fillRect(a[0], a[1], b[0] - a[0], b[1] - a[1]);
    ctx.restore();
    // Guide grid (SHEETGRID, SHT-011): screen only.
    const gs = this.sheetGrid;
    if (gs > 0 && gs * this.v.scale >= 4) {
      ctx.strokeStyle = "rgba(89,153,255,0.22)"; ctx.lineWidth = 0.5; ctx.beginPath();
      for (let x = 0; x <= p.w + 1e-9; x += gs) { const q = this.toView([x, 0]), r = this.toView([x, p.h]); ctx.moveTo(q[0], q[1]); ctx.lineTo(r[0], r[1]); }
      for (let y = 0; y <= p.h + 1e-9; y += gs) { const q = this.toView([0, y]), r = this.toView([p.w, y]); ctx.moveTo(q[0], q[1]); ctx.lineTo(r[0], r[1]); }
      ctx.stroke();
    }
    ctx.save();
    ctx.beginPath(); ctx.rect(a[0], a[1], b[0] - a[0], b[1] - a[1]); ctx.clip();
    applyView(ctx, this.v, d);
    const prm = { ...this.params(), lwScale: this.v.scale, minWidth: 0.12 * this.v.scale > 0.5 ? 0.12 * this.v.scale : 0.5 };
    // Viewport contents clipped to their frame or polygonal boundary (SHT-004 / SHT-008), then paper-space annotation.
    const groups = new Map<string, Item[]>(), paperItems: Item[] = [];
    for (const e of this.entries) for (const it of e.items) {
      const c = (it as any).clip as number[] | undefined;
      if (c) { const k = c.join(","); if (!groups.has(k)) groups.set(k, []); groups.get(k)!.push(it); } else paperItems.push(it);
    }
    for (const [k, items] of groups) {
      const r = k.split(",").map(Number);
      const vp = this.viewports.find((x) => x.rect.every((v, i) => Math.abs(v - r[i]) < 1e-3));
      ctx.save();
      ctx.beginPath();
      const offset = vp && this.vpDrag?.preview && this.vpDrag.index === vp.index ? [this.vpDrag.preview[0] - vp.rect[0], this.vpDrag.preview[1] - vp.rect[1]] : [0, 0];
      ctx.translate(offset[0], offset[1]);
      if (vp?.clip && vp.clip.length >= 3) { vp.clip.forEach((q, i) => (i ? ctx.lineTo(q[0], q[1]) : ctx.moveTo(q[0], q[1]))); ctx.closePath(); }
      else ctx.rect(r[0], r[1], r[2] - r[0], r[3] - r[1]);
      ctx.clip();
      paintItems(ctx, items, this.v, prm);
      ctx.restore();
    }
    paintItems(ctx, paperItems, this.v, prm);
    ctx.restore();
    ctx.setTransform(d, 0, 0, d, 0, 0);
    // Viewport borders: dashed blue, the selected one solid accent; lock badges.
    for (const vp of this.viewports) {
      const sel = this.selectedViewport === vp.index;
      const off = this.vpDrag?.preview && this.vpDrag.index === vp.index ? [this.vpDrag.preview[0] - vp.rect[0], this.vpDrag.preview[1] - vp.rect[1]] : [0, 0];
      ctx.save();
      ctx.strokeStyle = sel ? ACCENT : "rgba(77,140,230,0.8)"; ctx.lineWidth = sel ? 2 : 1;
      if (!sel) ctx.setLineDash([4, 3]);
      ctx.beginPath();
      const pts: V2[] = vp.clip && vp.clip.length >= 3 ? vp.clip : [[vp.rect[0], vp.rect[1]], [vp.rect[2], vp.rect[1]], [vp.rect[2], vp.rect[3]], [vp.rect[0], vp.rect[3]]];
      pts.forEach((q, i) => { const s = this.toView([q[0] + off[0], q[1] + off[1]]); if (i) ctx.lineTo(s[0], s[1]); else ctx.moveTo(s[0], s[1]); });
      ctx.closePath(); ctx.stroke();
      ctx.restore();
      if (vp.locked) {
        const q = this.toView([vp.rect[2] + off[0], vp.rect[3] + off[1]]);
        ctx.font = "12px 'Segoe UI Emoji', 'Segoe UI Symbol', sans-serif"; ctx.textBaseline = "top"; ctx.fillStyle = "#000"; ctx.fillText("🔒", q[0] - 18, q[1] + 4); ctx.textBaseline = "alphabetic";
      }
    }
    // Paper size label above the paper.
    const pct = Math.round((this.v.scale / (72 / 25.4)) * 100);
    ctx.font = `11px ${getComputedStyle(document.body).getPropertyValue("--ui")}`;
    ctx.fillStyle = "rgb(179,179,179)";
    ctx.fillText(`${p.name}  ${Math.round(p.w)} × ${Math.round(p.h)} mm  ·  ${pct}%`, a[0], a[1] - 8);
  }
  private viewportAt(v: V2): SheetVP | null {
    const q = this.toWorld(v[0], v[1]);
    for (let i = this.viewports.length - 1; i >= 0; i--) {
      const r = this.viewports[i].rect;
      if (q[0] >= r[0] && q[0] <= r[2] && q[1] >= r[1] && q[1] <= r[3]) return this.viewports[i];
    }
    return null;
  }
  private sheetDown(v: V2, e: MouseEvent) {
    if (e.detail === 2) { this.fitPaper(); return; }
    const vp = e.altKey ? null : this.viewportAt(v);
    if (vp) {
      this.selectedViewport = vp.index;
      this.vpDrag = { index: vp.index, start: v, origin: [vp.rect[0], vp.rect[1]], preview: null, pan: !!vp.locked };
    } else { this.selectedViewport = null; this.vpDrag = null; this.panLast = v; }
    this.contentDirty = true; this.schedule();
  }
  private sheetDrag(v: V2) {
    const d = this.vpDrag;
    if (!d) return;
    if (d.pan) { this.panLast = this.panLast ?? d.start; return; }
    const dx = (v[0] - d.start[0]) / this.v.scale, dy = -(v[1] - d.start[1]) / this.v.scale;
    let o: V2 = [d.origin[0] + dx, d.origin[1] + dy];
    if (this.sheetGrid > 0) o = [Math.round(o[0] / this.sheetGrid) * this.sheetGrid, Math.round(o[1] / this.sheetGrid) * this.sheetGrid];
    d.preview = o;
    this.contentDirty = true; this.schedule();
  }
  private async sheetUp() {
    const d = this.vpDrag;
    this.vpDrag = null;
    if (d?.preview && (Math.abs(d.preview[0] - d.origin[0]) > 1e-9 || Math.abs(d.preview[1] - d.origin[1]) > 1e-9)) {
      await this.app.tryCall("sheet.viewport", { index: d.index, op: "move", origin: d.preview, layout: this.app.info?.layouts[this.app.activeLayout - 1] });
      await this.app.refresh(["drawing", "history"]);
    }
    this.contentDirty = true; this.schedule();
  }
  private async sheetViewportOp(index: number, op: string, extra: Record<string, unknown> = {}) {
    const r = await this.app.tryCall("sheet.viewport", { index, op, layout: this.app.info?.layouts[this.app.activeLayout - 1], ...extra });
    if (!r && op !== "lock" && op !== "unlock") this.app.print("The viewport is locked (VPLOCK Off to unlock).");
    if (op === "remove" && r) this.selectedViewport = null;
    await this.app.refresh(["drawing", "history"]);
  }
  private sheetMenu(vp: SheetVP, at: V2) {
    const locked = !!vp.locked;
    const items: MenuItem[] = [{ header: `${vp.title || "Viewport " + (vp.index + 1)}  ${vp.ratioText ?? ""}` }];
    for (const s of [20, 50, 100, 200, 500]) items.push({ title: `Scale 1:${s}`, disabled: locked, action: () => this.sheetViewportOp(vp.index, "scale", { ratio: s }) });
    items.push({ separator: true });
    items.push({ title: locked ? "Unlock Viewport" : "Lock Viewport", action: () => this.sheetViewportOp(vp.index, locked ? "unlock" : "lock") });
    items.push({ title: "Maximise (VPMAX)", disabled: vp.view !== "plan" && vp.view !== "ceiling", action: () => this.app.runCommand(`VPMAX ${vp.index + 1}`) });
    if (vp.clip) items.push({ title: "Remove Clip", disabled: locked, action: () => this.sheetViewportOp(vp.index, "removeClip") });
    items.push({ title: "Remove", disabled: locked, action: () => this.sheetViewportOp(vp.index, "remove") });
    showMenu(items, { x: at[0], y: at[1] });
  }

  // ---- overlay ----
  private paintOverlay() {
    const ctx = this.overlay.getContext("2d")!;
    const d = this.dpr;
    ctx.setTransform(d, 0, 0, d, 0, 0);
    ctx.clearRect(0, 0, this.v.w, this.v.h);
    if (this.paper) { if (this.mouse && this.interactive && !this.panLast) this.crosshair(ctx, this.mouse, false, true); return; }
    const prm = this.params();
    applyView(ctx, this.v, d);
    if (this.hover && !this.app.selection.ids.includes(this.hover.id!)) paintItems(ctx, this.hover.items, this.v, prm, { colorOverride: "rgba(255,255,255,0.85)", extraWidth: 1.6, fillAlpha: 0.06, noText: false });
    const req = this.app.prompt;
    const pointish = req.active && req.kinds.some((k) => k === "point" || k === "distance" || k === "angle");
    if (pointish && this.preview.length && this.mouse) paintItems(ctx, this.preview, this.v, prm);
    // Dynamic UCS (PRC-036): the face that is (or would become) the work plane, with its axes, at the crosshair.
    if (req.active && req.kinds.includes("point") && this.mouse && this.ducs.length) {
      ctx.lineWidth = 2 / this.v.scale;
      for (const s of this.ducs) { ctx.strokeStyle = s.color; ctx.beginPath(); ctx.moveTo(s.from[0], s.from[1]); ctx.lineTo(s.to[0], s.to[1]); ctx.stroke(); }
      const o = this.ducs[0].from, r = 4 / this.v.scale;
      ctx.strokeStyle = ACCENT; ctx.beginPath(); ctx.arc(o[0], o[1], r, 0, Math.PI * 2); ctx.stroke();
    }
    // Grip drag preview and palette placement preview, in the accent colour.
    if (this.hot && this.hot.items.length) paintItems(ctx, this.hot.items, this.v, prm, { colorOverride: ACCENT });
    if (this.placement && this.placement.items.length && this.mouse) paintItems(ctx, this.placement.items, this.v, prm, { colorOverride: ACCENT });
    ctx.setTransform(d, 0, 0, d, 0, 0);
    // Rubber band from the base point.
    const base = this.hot ? this.hot.origin : pointish ? this.promptBase() : null;
    if (this.mouse && !this.win && base) {
      const a = this.toView(base), b = this.toView(this.cursorPoint());
      ctx.strokeStyle = "rgba(255,255,255,0.45)"; ctx.lineWidth = 1; ctx.setLineDash([5, 4]);
      ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke(); ctx.setLineDash([]);
    }
    // Lasso (SEL-007): counter-clockwise = crossing (green, dashed), clockwise = window (blue); rectangles by direction.
    const w = this.win;
    if (w?.lasso && w.lasso.length >= 2) {
      const crossing = w.lasso.length >= 3 && this.lassoCrossing(w.lasso);
      const c = crossing ? [64, 204, 102] : [77, 128, 255];
      ctx.beginPath(); w.lasso.forEach((p, i) => (i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1]))); ctx.closePath();
      ctx.fillStyle = `rgba(${c},0.13)`; ctx.fill();
      ctx.strokeStyle = `rgb(${c})`; ctx.lineWidth = 1; if (crossing) ctx.setLineDash([5, 3]); ctx.stroke(); ctx.setLineDash([]);
    } else if (w && (w.moved || Math.hypot(w.current[0] - w.start[0], w.current[1] - w.start[1]) > 2)) {
      const x = Math.min(w.start[0], w.current[0]), y = Math.min(w.start[1], w.current[1]);
      const ww = Math.abs(w.current[0] - w.start[0]), hh = Math.abs(w.current[1] - w.start[1]);
      const crossing = w.current[0] < w.start[0];
      const c = w.purpose === "zoom" ? [204, 204, 204] : crossing ? [64, 204, 102] : [77, 128, 255];
      ctx.fillStyle = `rgba(${c},0.13)`; ctx.fillRect(x, y, ww, hh);
      ctx.strokeStyle = `rgb(${c})`; ctx.lineWidth = 1; if (crossing && w.purpose !== "zoom") ctx.setLineDash([5, 3]);
      ctx.strokeRect(x + 0.5, y + 0.5, ww - 1, hh - 1); ctx.setLineDash([]);
    }
    this.paintTempDims(ctx);
    if (this.hoverGrip && !this.hot) this.gripMark(ctx, this.toView([this.hoverGrip.x, this.hoverGrip.y]), "rgb(255,115,140)");
    if (this.hot) this.gripMark(ctx, this.toView(this.hot.origin), "rgb(230,51,51)");
    // Object snap tracking: acquired points and alignment vectors (OTRACK), only while a command runs.
    if (this.mouse && !this.app.isIdle && this.tracking) this.paintTracking(ctx);
    const sn = this.hot ? this.hot.snap : this.snap;
    if (sn && this.mouse) this.snapMarker(ctx, sn);
    if (this.mouse && !this.panLast && this.interactive) {
      const pickbox = (this.app.isIdle && !this.hot) || (req.active && req.kinds.some((k) => k === "selection" || k === "entity") && !req.kinds.includes("point"));
      this.crosshair(ctx, this.mouse, pickbox);
      if (this.app.sysvarOn("DYNMODE")) this.dynamicInput(ctx, this.mouse);
    }
  }
  private lassoCrossing(pts: V2[]) {
    // Signed area in world coordinates (y up): counter-clockwise (> 0) = crossing (SelectionGeometry.lassoMode).
    const wp = pts.map((p) => this.toWorld(p[0], p[1]));
    let a = 0;
    for (let i = 0; i < wp.length; i++) { const p = wp[i], q = wp[(i + 1) % wp.length]; a += p[0] * q[1] - q[0] * p[1]; }
    return a > 0;
  }
  private promptBase(): V2 | null {
    const p = this.app.prompt;
    if (!p.active || !p.base) return null;
    const b: any = p.base;
    return Array.isArray(b) ? [b[0], b[1]] : [b.x, b.y];
  }
  private engineCursor: V2 | null = null;
  private cursorPoint(): V2 {
    if (this.hot?.point) return this.hot.point;
    return this.snap ? snapPoint(this.snap) : this.engineCursor ?? this.world;
  }
  private gripMark(ctx: CanvasRenderingContext2D, v: V2, col: string) {
    const sz = 8, r = [Math.round(v[0] - sz / 2) + 0.5, Math.round(v[1] - sz / 2) + 0.5];
    ctx.fillStyle = col; ctx.fillRect(r[0], r[1], sz, sz); ctx.strokeStyle = "rgba(255,255,255,0.9)"; ctx.lineWidth = 1; ctx.strokeRect(r[0], r[1], sz, sz);
  }
  private crosshair(ctx: CanvasRenderingContext2D, v: V2, pickbox: boolean, arrow = false) {
    if (arrow) return; // the sheet canvas uses the system arrow cursor
    const pct = Math.min(Math.max(prefs.cursorSize, 1), 100);
    const arm = pct >= 100 ? Math.max(this.v.w, this.v.h) * 2 : Math.max(8, (pct / 200) * Math.max(this.v.w, this.v.h));
    const x = Math.round(v[0]) + 0.5, y = Math.round(v[1]) + 0.5, gap = pickbox ? 5 : 0;
    ctx.lineWidth = 1; ctx.strokeStyle = "rgba(242,242,242,0.95)";
    ctx.beginPath();
    ctx.moveTo(x - arm, y); ctx.lineTo(x - gap, y); ctx.moveTo(x + gap, y); ctx.lineTo(x + arm, y);
    ctx.moveTo(x, y - arm); ctx.lineTo(x, y - gap); ctx.moveTo(x, y + gap); ctx.lineTo(x, y + arm);
    ctx.stroke();
    if (pickbox) ctx.strokeRect(x - 5, y - 5, 10, 10);
  }
  /** Acquired tracking points (small crosses), the active tracking vectors (dotted rays) and the tracking readout. */
  private paintTracking(ctx: CanvasRenderingContext2D) {
    const tr = this.tracking!;
    if (!tr.points.length && !tr.lines.length) return;
    ctx.save();
    ctx.strokeStyle = "rgba(89,217,115,0.95)"; ctx.lineWidth = 1;
    ctx.beginPath();
    for (const p of tr.points) { const v = this.toView(p), s = 4; ctx.moveTo(v[0] - s, v[1]); ctx.lineTo(v[0] + s, v[1]); ctx.moveTo(v[0], v[1] - s); ctx.lineTo(v[0], v[1] + s); }
    ctx.stroke();
    const reach = Math.hypot(this.v.w, this.v.h);
    ctx.setLineDash([2, 4]); ctx.beginPath();
    for (const l of tr.lines) {
      const a = this.toView(l.from), b = this.toView(l.to), dx = b[0] - a[0], dy = b[1] - a[1], len = Math.hypot(dx, dy);
      if (len <= 0.5) continue;
      ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0] + (dx / len) * reach, b[1] + (dy / len) * reach);
    }
    ctx.stroke(); ctx.restore();
    const sn = this.snap, l = tr.lines[tr.lines.length - 1];
    if (l && sn && (sn.kind === "extension" || sn.kind === "parallel")) {
      const p = snapPoint(sn), dx = p[0] - l.from[0], dy = p[1] - l.from[1], dist = Math.hypot(dx, dy);
      if (dist <= 1e-9) return;
      let ang = (Math.atan2(dy, dx) * 180) / Math.PI; if (ang < 0) ang += 360;
      const v = this.toView(p);
      ctx.save(); ctx.strokeStyle = "rgb(89,217,115)"; ctx.lineWidth = 1.5; ctx.beginPath();
      ctx.moveTo(v[0] - 5, v[1] - 5); ctx.lineTo(v[0] + 5, v[1] + 5); ctx.moveTo(v[0] - 5, v[1] + 5); ctx.lineTo(v[0] + 5, v[1] - 5); ctx.stroke(); ctx.restore();
      const label = tr.lines.length > 1 ? "Intersection of tracking paths" : `Tracking: ${fmt(dist, 2)} < ${fmt(ang, 1)}°`;
      this.tooltip(ctx, [label], [v[0] + 12, v[1] + 32]);
    }
  }
  private snapMarker(ctx: CanvasRenderingContext2D, sn: SnapInfo) {
    const [cx, cy] = this.toView(snapPoint(sn)), s = 6;
    ctx.save(); ctx.strokeStyle = ACCENT; ctx.lineWidth = 2; ctx.beginPath();
    const Y = (dy: number) => cy - dy; // Mac draws with y up
    switch (sn.kind) {
      case "endpoint": ctx.rect(cx - s, cy - s, 2 * s, 2 * s); break;
      case "midpoint": ctx.moveTo(cx - s, Y(-s * 0.8)); ctx.lineTo(cx + s, Y(-s * 0.8)); ctx.lineTo(cx, Y(s * 1.1)); ctx.closePath(); break;
      case "center": ctx.arc(cx, cy, s, 0, Math.PI * 2); break;
      case "node": ctx.arc(cx, cy, s, 0, Math.PI * 2); ctx.moveTo(cx - s * 0.7, cy - s * 0.7); ctx.lineTo(cx + s * 0.7, cy + s * 0.7); ctx.moveTo(cx - s * 0.7, cy + s * 0.7); ctx.lineTo(cx + s * 0.7, cy - s * 0.7); break;
      case "quadrant": ctx.moveTo(cx, cy - s); ctx.lineTo(cx + s, cy); ctx.lineTo(cx, cy + s); ctx.lineTo(cx - s, cy); ctx.closePath(); break;
      case "intersection": ctx.moveTo(cx - s, cy - s); ctx.lineTo(cx + s, cy + s); ctx.moveTo(cx - s, cy + s); ctx.lineTo(cx + s, cy - s); break;
      case "extension": for (const dx of [-s, 0, s]) { ctx.moveTo(cx + dx + 1.2, cy); ctx.arc(cx + dx, cy, 1.2, 0, Math.PI * 2); } break;
      case "insertion": ctx.rect(cx - s, Y(-s * 0.2) - s * 1.2, s * 1.2, s * 1.2); ctx.rect(cx - s * 0.2, Y(-s) - s * 1.2, s * 1.2, s * 1.2); break;
      case "perpendicular": ctx.moveTo(cx - s, Y(s)); ctx.lineTo(cx - s, Y(-s)); ctx.lineTo(cx + s, Y(-s)); ctx.moveTo(cx - s, cy); ctx.lineTo(cx, cy); ctx.lineTo(cx, Y(-s)); break;
      case "tangent": ctx.arc(cx, cy, s * 0.8, 0, Math.PI * 2); ctx.moveTo(cx - s, Y(s * 0.8)); ctx.lineTo(cx + s, Y(s * 0.8)); break;
      case "nearest": ctx.moveTo(cx - s, Y(s)); ctx.lineTo(cx + s, Y(s)); ctx.lineTo(cx - s, Y(-s)); ctx.lineTo(cx + s, Y(-s)); ctx.closePath(); break;
      case "parallel": ctx.moveTo(cx - s, Y(-s * 0.3)); ctx.lineTo(cx - s * 0.1, Y(s)); ctx.moveTo(cx + s * 0.1, Y(-s)); ctx.lineTo(cx + s, Y(s * 0.3)); break;
      default: ctx.moveTo(cx - s, cy); ctx.lineTo(cx + s, cy); ctx.moveTo(cx, cy - s); ctx.lineTo(cx, cy + s);
    }
    ctx.stroke(); ctx.restore();
    this.tooltip(ctx, [cap(sn.kind)], [cx + 10, cy + 12], true);
  }
  /** Small dark tooltip box; `at` is its top-left corner (screen, y down). */
  private tooltip(ctx: CanvasRenderingContext2D, lines: (string | { fields: { label: string; value: string; active: boolean; locked: boolean }[] })[], at: V2, accent = false) {
    if (!lines.length) return;
    ctx.font = `10.5px ${getComputedStyle(document.body).getPropertyValue("--mono")}`;
    const lineW = (l: (typeof lines)[number]) => typeof l === "string" ? ctx.measureText(l).width : l.fields.reduce((a, f) => a + ctx.measureText(f.label).width + Math.max(46, ctx.measureText(f.value).width + 10) + 14, 0);
    const w = Math.max(...lines.map(lineW)) + 12, lh = 14, hh = lines.length * lh + 6;
    let x = at[0], y = at[1];
    if (x + w > this.v.w - 4) x = this.v.w - w - 4;
    if (y + hh > this.v.h - 4) y = at[1] - hh - 24;
    ctx.beginPath(); (ctx as any).roundRect ? (ctx as any).roundRect(x, y, w, hh, 3) : ctx.rect(x, y, w, hh);
    ctx.fillStyle = "rgba(43,44,49,0.96)"; ctx.fill();
    ctx.strokeStyle = accent ? "rgba(245,197,24,0.6)" : "rgba(255,255,255,0.14)"; ctx.lineWidth = 1; ctx.stroke();
    ctx.textBaseline = "alphabetic";
    lines.forEach((l, i) => {
      const by = y + 3 + (i + 1) * lh - 3;
      if (typeof l === "string") { ctx.fillStyle = accent ? ACCENT : "#E6E6E6"; ctx.fillText(l, x + 6, by); return; }
      // Dynamic-input fields: label, then a boxed value; the field being typed has the accent outline.
      let fx = x + 6;
      for (const f of l.fields) {
        ctx.fillStyle = "#9A9BA1"; ctx.fillText(f.label, fx, by); fx += ctx.measureText(f.label).width + 4;
        const bw = Math.max(46, ctx.measureText(f.value).width + 10);
        ctx.fillStyle = f.active ? "rgba(245,197,24,0.16)" : "rgba(27,28,31,0.95)"; ctx.fillRect(fx, by - 11, bw, 14);
        ctx.strokeStyle = f.active ? ACCENT : "rgba(255,255,255,0.18)"; ctx.strokeRect(fx + 0.5, by - 10.5, bw - 1, 13);
        ctx.fillStyle = f.locked ? ACCENT : "#E6E6E6"; ctx.fillText(f.value + (f.active ? "▏" : ""), fx + 5, by);
        fx += bw + 10;
      }
    });
  }
  private dynamicInput(ctx: CanvasRenderingContext2D, v: V2) {
    const req = this.app.prompt, lines: Parameters<PlanCanvas["tooltip"]>[1] = [];
    const cp = this.cursorPoint();
    if (req.active) {
      lines.push((req.label ?? req.message.replace(/\s*\[[^\]]*\]/, "").replace(/:\s*$/, "")) + (req.keywords.length ? "  [" + req.keywords.join("/") + "]" : ""));
      if (req.kinds.some((k) => k === "point" || k === "distance" || k === "angle")) {
        const b = this.hot?.origin ?? this.promptBase();
        const f = this.dyn;
        let len: number | undefined, ang: number | undefined;
        if (f && f.length !== undefined) { len = f.length; ang = f.angle; }
        else if (b) { const dx = cp[0] - b[0], dy = cp[1] - b[1]; len = Math.hypot(dx, dy); ang = (Math.atan2(dy, dx) * 180) / Math.PI; if (ang < 0) ang += 360; }
        const di = this.dynInput, typing = this.app.commandInput;
        if (len !== undefined) {
          if (di || this.isNumeric(typing)) {
            const vals = di?.values ?? ["", ""], fld = di?.field ?? 0;
            const shown = (k: 0 | 1, live: string) => (fld === k && typing ? typing : vals[k] || live);
            lines.push({ fields: [{ label: "L", value: shown(0, fmt(len, 2)), active: fld === 0, locked: !!vals[0] }, { label: "∠", value: shown(1, fmt(ang ?? 0, 1) + "°"), active: fld === 1, locked: !!vals[1] }] });
          } else lines.push(`L ${fmt(len, 2)}   ∠ ${fmt(ang ?? 0, 1)}°`);
        } else {
          const x = f?.x ?? cp[0], y = f?.y ?? cp[1];
          if (di || this.isNumeric(typing)) {
            const vals = di?.values ?? ["", ""], fld = di?.field ?? 0;
            const shown = (k: 0 | 1, live: string) => (fld === k && typing ? typing : vals[k] || live);
            lines.push({ fields: [{ label: "X", value: shown(0, fmt(x, 2)), active: fld === 0, locked: !!vals[0] }, { label: "Y", value: shown(1, fmt(y, 2)), active: fld === 1, locked: !!vals[1] }] });
          } else lines.push(`X ${fmt(x, 2)}   Y ${fmt(y, 2)}`);
        }
      }
    } else if (this.hot) {
      const g = this.hot, dx = cp[0] - g.origin[0], dy = cp[1] - g.origin[1];
      let a = (Math.atan2(dy, dx) * 180) / Math.PI; if (a < 0) a += 360;
      if (g.action) lines.push(`${g.actionTitle ?? g.action}  (Esc cancels)`);
      else if (g.mode !== "stretch" || !g.dragging) lines.push(`** ${g.mode.toUpperCase()}${g.copy ? " (multiple)" : ""} **  Space: next mode · type a value · C copy · MO RO SC MI ST`);
      else lines.push(g.turns % 4 === 0 ? "Stretch point  (Space rotates 90°)" : `Stretch point, rotated ${(((g.turns % 4) + 4) % 4) * 90}°  (Space: +90°, Shift+Space: −90°)`);
      lines.push(`L ${fmt(Math.hypot(dx, dy), 2)}   ∠ ${fmt(a, 1)}°`);
    }
    if (this.app.commandInput && !(this.dynInput || (req.active && this.isNumeric(this.app.commandInput) && req.kinds.includes("point")))) lines.push("› " + this.app.commandInput);
    if (lines.length) this.tooltip(ctx, lines, [v[0] + 20, v[1] + 18]);
  }
  private isNumeric(s: string) { return /^-?\d*[.,]?\d+$/.test(s.trim()) || /^-?\d+[.,]$/.test(s.trim()); }

  // ---- input ----
  private bind() {
    const o = this.overlay;
    const pos = (e: MouseEvent): V2 => { const r = o.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
    o.addEventListener("contextmenu", (e) => e.preventDefault());
    o.addEventListener("mouseleave", () => {
      this.mouse = null; this.hover = null; this.hoverGrip = null; this.snap = null; this.app.live.snapHint = this.hint;
      this.overlayDirty = true; this.schedule();
    });
    o.addEventListener("mousemove", (e) => this.move(pos(e), e));
    o.addEventListener("mousedown", (e) => { e.preventDefault(); this.down(pos(e), e); });
    addEventListener("mousemove", (e) => { if (this.radial || (this.panLast && e.target !== o) || (this.win && e.target !== o) || (this.hot?.dragging && e.target !== o) || (this.vpDrag && e.target !== o)) this.move(pos(e), e); });
    addEventListener("mouseup", (e) => this.up(pos(e), e));
    o.addEventListener("wheel", (e) => this.wheel(e, pos(e)), { passive: false });
    o.addEventListener("keydown", (e) => { if (e.code === "Space" && this.app.commandInput === "" && !e.repeat && !this.placement && !this.hot) { this.spaceDown = true; this.spacePanned = false; } });
    o.addEventListener("keyup", (e) => { if (e.code === "Space") { this.spaceDown = false; this.panLast = null; } });
    // Keys the Mac canvas handles itself, ahead of the main window keyboard handler (main.ts).
    addEventListener("keydown", (e) => this.keyDown(e), true);
    addEventListener("keyup", (e) => {
      if (e.key !== " " || !this.el.isConnected) return;
      // Space released: Enter unless it cycled a grip mode / rotated, or panned with Space+drag (CanvasView.keyUp).
      if (this.swallowSpaceUp || this.spacePanned) { e.stopImmediatePropagation(); e.preventDefault(); }
      this.swallowSpaceUp = false; this.spaceDown = false; this.spacePanned = false; this.panLast = null; this.resetCursor();
    }, true);
    // Drag and drop: palette items (blocks, components, commands, materials) and files (IO-065).
    o.addEventListener("dragover", (e) => {
      const t = e.dataTransfer?.types ?? [];
      if (t.includes("Files") || t.includes(DROP_TYPE)) { e.preventDefault(); e.dataTransfer!.dropEffect = "copy"; const p = pos(e); this.mouse = p; this.world = this.toWorld(p[0], p[1]); this.app.live.x = this.world[0]; this.app.live.y = this.world[1]; this.app.emit("live"); }
    });
    o.addEventListener("drop", (e) => { void this.drop(e, pos(e)); });
  }
  private wheel(e: WheelEvent, p: V2) {
    e.preventDefault();
    const wd = (e as any).wheelDeltaY as number | undefined;
    const mouseWheel = e.deltaMode !== 0 || (wd !== undefined && wd !== 0 && Math.abs(wd) % 120 === 0 && e.deltaX === 0);
    if (e.ctrlKey && !mouseWheel) this.zoomBy(Math.exp(-e.deltaY * 0.01), p); // precision touchpad pinch
    else if (e.ctrlKey || (mouseWheel && !e.shiftKey)) this.zoomBy(Math.pow(1.2, -Math.sign(e.deltaY) * Math.max(1, Math.abs(e.deltaY) / (e.deltaMode === 1 ? 3 : 100))), p);
    else if (e.shiftKey && mouseWheel) this.panView(-e.deltaY, 0);
    else this.panView(-e.deltaX, -e.deltaY); // touchpad two-finger scroll
    this.move(p, e);
  }
  private gripAt(v: V2) {
    let best: Grip | null = null, bd = Infinity;
    for (const g of this.grips) { const p = this.toView([g.x, g.y]); const d = Math.max(Math.abs(p[0] - v[0]), Math.abs(p[1] - v[1])); if (d <= 6 && d < bd) { bd = d; best = g; } }
    return best;
  }
  private flipAt(v: V2) { return this.flips.find((f) => { const p = this.toView(f.point); return Math.hypot(p[0] - v[0], p[1] - v[1]) <= 8; }) ?? null; }
  private tempDimAt(v: V2) { return this.tempDimBoxes.find((b) => v[0] >= b.box[0] && v[0] <= b.box[0] + b.box[2] && v[1] >= b.box[1] && v[1] <= b.box[1] + b.box[3])?.td ?? null; }
  private move(v: V2, e: MouseEvent) {
    this.mouse = v;
    if (this.radial) { this.radialDrag(v, e); return; }
    if (this.panLast) {
      this.panView(v[0] - this.panLast[0], v[1] - this.panLast[1]);
      this.panLast = v; if (this.spaceDown) this.spacePanned = true; return;
    }
    this.world = this.toWorld(v[0], v[1]);
    if (this.paper) {
      if (this.vpDrag && e.buttons & 1) { if (this.vpDrag.pan) { this.panLast = v; } else this.sheetDrag(v); }
      this.app.live.x = this.world[0]; this.app.live.y = this.world[1]; this.app.emit("live");
      return;
    }
    if (this.win) {
      this.win.current = v;
      if (Math.hypot(v[0] - this.win.start[0], v[1] - this.win.start[1]) > 4) this.win.moved = true;
      const last = this.win.lasso?.[this.win.lasso.length - 1];
      if (last && Math.hypot(v[0] - last[0], v[1] - last[1]) > 3) this.win.lasso!.push(v);
    }
    if (this.hot?.dragging && Math.hypot(v[0] - this.hot.startView[0], v[1] - this.hot.startView[1]) > 4) this.hot.moved = true;
    const app = this.app, req = app.prompt;
    const wantsPoint = (req.active && req.kinds.some((k) => ["point", "distance", "angle"].includes(k))) || !!this.hot;
    const wantsPick = !this.hot && !this.win && !this.panLast && (app.isIdle || (req.active && req.kinds.some((k) => k === "selection" || k === "entity") && !req.kinds.includes("point")));
    // SELECTIONPREVIEW: 1 = highlight when idle, 2 = during selection prompts, 3 = both (SEL-019).
    const sp = this.state.selectionPreview ?? 3;
    const previewOn = app.isIdle ? (sp & 1) !== 0 : (sp & 2) !== 0;
    this.hover = wantsPick && previewOn ? pick(this.entries, this.world, 6 / this.v.scale) : null;
    this.hoverGrip = app.isIdle && !this.hot ? this.gripAt(v) : null;
    if (this.hot) this.sendGripPreview();
    else if (wantsPoint) this.sendCursor();
    else {
      this.snap = null; this.engineCursor = null; this.tracking = null; this.dyn = null; this.ducs = [];
      if (this.placement) this.sendPlacementPreview();
    }
    if (!this.hot && !wantsPoint && !this.placement && !this.cycle) app.live.snapHint = this.hint;
    const cp = this.cursorPoint();
    app.live.x = cp[0]; app.live.y = cp[1];
    app.emit("live");
    this.overlayDirty = true; this.schedule();
  }
  /** input.cursor: previews, snaps, tracking and dynamic-input fields come from the engine; one request in flight. */
  private async sendCursor() {
    if (this.cursorBusy) { this.cursorPending = true; return; }
    this.cursorBusy = true;
    const [x, y] = this.world;
    const st = await this.app.tryCall("input.cursor", { x, y, pixelsPerUnit: this.v.scale });
    this.cursorBusy = false;
    if (st && typeof st === "object") {
      this.snap = st.snap ?? null;
      this.engineCursor = Array.isArray(st.cursor) ? [st.cursor[0], st.cursor[1]] : null;
      this.tracking = st.tracking && (st.tracking.points || st.tracking.lines) ? { points: st.tracking.points ?? [], lines: st.tracking.lines ?? [] } : null;
      this.dyn = st.dynamic ?? null;
      this.ducs = Array.isArray(st.ducs) ? st.ducs : [];
      this.app.live.snapHint = this.snap ? cap(this.snap.kind) : "";
      this.preview = (st.preview ?? []).map(decodeItem).filter(Boolean) as Item[];
      const p = this.app.prompt;
      if (st.active !== p.active || st.message !== p.message || JSON.stringify(st.keywords) !== JSON.stringify(p.keywords)) this.app.setPrompt(st);
      else { p.base = st.base ?? p.base; }
      this.overlayDirty = true; this.schedule();
    }
    if (this.cursorPending) { this.cursorPending = false; this.sendCursor(); }
  }
  private gripBusy = false;
  private gripPending = false;
  /** grips.preview: the grip-drag preview of the hot grip at the cursor (stretch, a grip mode or a grip-menu action). */
  private async sendGripPreview() {
    if (this.gripBusy) { this.gripPending = true; return; }
    const g = this.hot;
    if (!g) return;
    this.gripBusy = true;
    const r = await this.app.tryCall("grips.preview", { id: g.grip.id, index: g.grip.index, x: this.world[0], y: this.world[1], mode: g.mode, action: g.action ?? undefined,
      turns: g.turns, reference: g.reference, pixelsPerUnit: this.v.scale });
    this.gripBusy = false;
    if (r && this.hot === g) {
      g.items = (r.items ?? []).map(decodeItem).filter(Boolean) as Item[];
      g.point = Array.isArray(r.point) ? [r.point[0], r.point[1]] : null;
      g.snap = r.snap ?? null;
      if (g.reference === undefined && typeof r.reference === "number") g.reference = r.reference;
      this.app.live.snapHint = g.snap ? cap(g.snap.kind) : this.hint;
      this.overlayDirty = true; this.schedule();
    }
    if (this.gripPending) { this.gripPending = false; this.sendGripPreview(); }
  }
  private placeBusy = false;
  private async sendPlacementPreview() {
    const pl = this.placement;
    if (!pl || this.placeBusy) return;
    this.placeBusy = true;
    const r = await this.app.tryCall("place.preview", { item: pl.item, x: this.world[0], y: this.world[1], turns: pl.turns });
    this.placeBusy = false;
    if (r && this.placement === pl) { pl.items = (r.items ?? []).map(decodeItem).filter(Boolean) as Item[]; this.overlayDirty = true; this.schedule(); }
  }

  private down(v: V2, e: MouseEvent) {
    InPlaceTextEditor.current?.commit();
    closeMenus();
    this.focus();
    this.mouse = v;
    this.world = this.toWorld(v[0], v[1]);
    if (e.button === 2) { this.rightDown(v, e); return; }
    if (e.button === 1 || (e.button === 0 && this.spaceDown)) {
      if (e.button === 1 && performance.now() - this.lastMiddle < 350) { this.zoomExtents(); this.lastMiddle = 0; return; }
      if (e.button === 1) this.lastMiddle = performance.now();
      if (this.spaceDown) this.spacePanned = true;
      this.panLast = v; this.overlay.style.cursor = "grabbing"; return;
    }
    if (e.button !== 0) return;
    if (this.paper) { this.sheetDown(v, e); return; }
    const app = this.app, req = app.prompt, w = this.world;
    if (this.win) { this.win.current = v; this.finishWindow(e.shiftKey); return; }
    if (this.hot && !this.hot.dragging) { void this.commitGrip(); return; }
    if (this.zoomWindowPending) { this.win = { start: v, current: v, moved: false, purpose: "zoom", shift: false, lasso: null }; return; }
    if (req.active) {
      // The engine applies running snaps, grid snap and ortho/polar from the base point (input.point snap:true).
      if (req.kinds.includes("point")) {
        const tok = this.dynToken(true);
        if (tok) { void app.submitLine(tok); return; }
        app.tryCall("input.point", { x: w[0], y: w[1], snap: true, pixelsPerUnit: this.v.scale }).then((st) => st && app.setPrompt(st)); return;
      }
      if (req.kinds.some((k) => k === "selection" || k === "entity")) {
        const hit = pick(this.entries, w, 6 / this.v.scale);
        if (hit) { app.tryCall("pick", { x: w[0], y: w[1], tolerance: 6 / this.v.scale, add: true, toggle: e.shiftKey }).then((r) => { if (r?.prompt) app.setPrompt(r.prompt); app.refresh(["selection"]); }); }
        else if (req.kinds.includes("selection")) this.win = { start: v, current: v, moved: false, purpose: "request", shift: e.shiftKey, lasso: e.altKey ? [v] : null };
      }
      return;
    }
    if (!app.isIdle) return;
    if (this.placement) { void this.placeAt(w, e.shiftKey); return; }
    const td = this.tempDimAt(v);
    if (td) { this.editTempDim(td, v); return; }
    if (e.detail === 2) { const hit = pick(this.entries, w, 6 / this.v.scale); if (hit?.id) { void this.editObject(Number(hit.id)); return; } }
    const f = this.flipAt(v);
    if (f) { void app.tryCall("flips.apply", { id: f.id, kind: f.kind }).then(() => app.refresh(["drawing", "selection", "history"])); return; }
    const g = this.gripAt(v);
    if (g) {
      this.hot = { grip: g, origin: [g.x, g.y], startView: v, moved: false, dragging: true, turns: 0, mode: "stretch", copy: false, action: null, actionTitle: null, items: [], point: null, snap: null };
      this.hoverGrip = null;
      this.sendGripPreview();
      return;
    }
    if (!e.shiftKey && this.cycleSelection(w)) return;
    const hit = pick(this.entries, w, 6 / this.v.scale);
    if (hit) {
      app.tryCall("pick", { x: w[0], y: w[1], tolerance: 6 / this.v.scale, add: true, toggle: e.shiftKey }).then(async (r) => {
        await app.refresh(["selection", "properties"]);
        if (hit.id) await this.startCycle(w, r?.hit != null ? String(r.hit) : hit.id);
      });
      return;
    }
    this.win = { start: v, current: v, moved: false, purpose: "select", shift: e.shiftKey, lasso: e.altKey ? [v] : null };
  }
  private up(v: V2, e: MouseEvent) {
    if (e.button === 2) { this.rightUp(v, e); return; }
    if (this.panLast && (e.button === 1 || e.button === 0)) { this.panLast = null; this.resetCursor(); if (this.paper) this.vpDrag = null; return; }
    if (this.paper) { if (e.button === 0) void this.sheetUp(); return; }
    if (this.hot?.dragging && e.button === 0) {
      if (this.hot.moved) void this.commitGrip(); else this.hot.dragging = false; // click-click grip editing
      return;
    }
    const w = this.win;
    if (w && e.button === 0 && (w.moved || w.lasso && w.lasso.length > 2)) this.finishWindow(e.shiftKey);
    this.overlayDirty = true; this.schedule();
  }
  private finishWindow(shift: boolean) {
    const w = this.win;
    if (!w) return;
    this.win = null;
    const app = this.app;
    if (w.lasso) {
      if (w.purpose === "zoom" || w.lasso.length < 3) return;
      const pts = w.lasso.map((p) => this.toWorld(p[0], p[1]));
      app.tryCall("select.lasso", { points: pts, remove: shift && w.purpose === "select" }).then((r) => { if (r?.prompt) app.setPrompt(r.prompt); app.refresh(["selection", "properties"]); });
      return;
    }
    if (Math.abs(w.current[0] - w.start[0]) <= 2 && Math.abs(w.current[1] - w.start[1]) <= 2) { if (w.purpose === "zoom") this.zoomWindowPending = false; return; }
    const a = this.toWorld(w.start[0], w.start[1]), b = this.toWorld(w.current[0], w.current[1]);
    if (w.purpose === "zoom") {
      this.zoomWindowPending = false;
      this.zoomTo([Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[0], b[0]), Math.max(a[1], b[1])]);
      return;
    }
    const crossing = w.current[0] < w.start[0];
    app.tryCall("select.window", { x0: a[0], y0: a[1], x1: b[0], y1: b[1], crossing, add: true, remove: shift && w.purpose === "select" }).then((r) => { if (r?.prompt) app.setPrompt(r.prompt); app.refresh(["selection", "properties"]); });
    this.overlayDirty = true; this.schedule();
  }

  // ---- selection cycling (SEL-018) ----
  private async startCycle(w: V2, first: string) {
    const r = await this.app.tryCall("pick.candidates", { x: w[0], y: w[1], tolerance: 6 / this.v.scale });
    const ids: string[] = [first, ...((r?.ids ?? []) as any[]).map(String).filter((x: string) => x !== first)];
    this.cycle = ids.length > 1 ? { point: w, ids, index: 0 } : null;
    if (this.cycle) this.setHint(`1 of ${ids.length} overlapping objects — click again to cycle`);
  }
  private cycleSelection(w: V2): boolean {
    const c = this.cycle;
    if (!c) return false;
    if (Math.hypot(c.point[0] - w[0], c.point[1] - w[1]) > 6 / this.v.scale || !this.app.selection.ids.includes(c.ids[c.index])) { this.cycle = null; return false; }
    const prev = c.ids[c.index];
    c.index = (c.index + 1) % c.ids.length;
    const next = c.ids[c.index];
    void this.app.tryCall("select.modify", { remove: [Number(prev)], add: [Number(next)] }).then(async () => {
      await this.app.refresh(["selection", "properties"]);
      const r = await this.app.tryCall("pick.candidates", { x: c.point[0], y: c.point[1], tolerance: 6 / this.v.scale });
      const k = (r?.ids ?? []).map(String).indexOf(next);
      const kind = k >= 0 ? r.types?.[k] ?? "object" : "object";
      this.setHint(`${c.index + 1} of ${c.ids.length}: ${kind} #${next}`);
    });
    return true;
  }
  private cycleCheck() { if (this.cycle && !this.app.selection.ids.includes(this.cycle.ids[this.cycle.index])) this.cycle = null; }
  private setHint(s: string) { this.hint = s; this.app.live.snapHint = s; this.app.emit("live"); }

  // ---- grips (SEL-032…SEL-038) ----
  private async commitGrip() {
    const g = this.hot;
    if (!g) return;
    this.hot = null;
    const p = g.point ?? this.world;
    const params: any = { id: g.grip.id, index: g.grip.index, x: p[0], y: p[1], mode: g.mode, copy: g.copy, turns: g.turns, reference: g.reference, pixelsPerUnit: this.v.scale };
    if (g.action) params.action = g.action;
    const moved = Math.hypot(p[0] - g.origin[0], p[1] - g.origin[1]) > 1e-12 || ((g.turns % 4) + 4) % 4 !== 0 || g.mode !== "stretch" || !!g.action;
    if (moved) await this.app.tryCall("grips.edit", params);
    if (g.copy && !g.action) this.hot = { ...g, dragging: false, moved: false, items: [] }; // Copy keeps the grip hot for more copies
    this.setHint("");
    await this.app.refresh(["drawing", "selection", "properties", "history"]);
  }
  /** A line typed while a grip is hot (SEL-034 keywords, SEL-038 values); false when no grip is hot. */
  handleGripInput(line: string): boolean {
    const g = this.hot;
    if (!g) return false;
    const t = line.trim().toUpperCase();
    const done = () => { this.overlayDirty = true; this.schedule(); return true; };
    if (!t) { g.mode = GRIP_MODES[(GRIP_MODES.indexOf(g.mode) + 1) % GRIP_MODES.length]; this.setHint(`Grip mode: ${cap(g.mode)}`); g.items = []; this.sendGripPreview(); return done(); }
    if (t === "C" || t === "COPY") { g.copy = !g.copy; this.setHint(g.copy ? "Copy on: each click places a copy" : "Copy off"); return done(); }
    if (t === "X" || t === "EXIT") { this.hot = null; this.setHint(""); return done(); }
    if (MODE_KEYWORDS[t]) { g.mode = MODE_KEYWORDS[t]; this.setHint(`Grip mode: ${cap(g.mode)}`); g.items = []; this.sendGripPreview(); return done(); }
    // A typed point: x,y (absolute) or @dx,dy (relative to the grip).
    const parts = t.replace("@", "").split(",").map((s) => Number(s.trim()));
    if (parts.length === 2 && parts.every((n) => isFinite(n))) {
      g.point = t.startsWith("@") ? [g.origin[0] + parts[0], g.origin[1] + parts[1]] : [parts[0], parts[1]];
      void this.commitGrip();
      return done();
    }
    const val = Number(t.replace(",", "."));
    if (!isFinite(val) || !t) { this.setHint("Enter a distance, a point, or MO/RO/SC/MI/ST/C/X"); return done(); }
    const dir = g.point ?? this.world;
    if (g.mode === "stretch" && (g.action || g.turns % 4 !== 0)) {
      const dx = dir[0] - g.origin[0], dy = dir[1] - g.origin[1], l = Math.hypot(dx, dy);
      g.point = l > 0 ? [g.origin[0] + (dx / l) * val, g.origin[1] + (dy / l) * val] : [g.origin[0] + val, g.origin[1]];
      void this.commitGrip();
      return done();
    }
    const keep = g.copy && g.mode !== "stretch";
    void this.app.tryCall("grips.typed", { id: g.grip.id, index: g.grip.index, mode: g.mode, value: val, x: dir[0], y: dir[1], copy: g.copy })
      .then(() => this.app.refresh(["drawing", "selection", "properties", "history"]));
    if (!keep) this.hot = null;
    return done();
  }
  /** Makes grip `index` of an object hot, as a click on it does (scripts and tests). */
  async makeGripHot(id: number | string, index: number) {
    const g = this.grips.find((x) => String(x.id) === String(id) && x.index === index);
    if (!g) return false;
    this.hot = { grip: g, origin: [g.x, g.y], startView: this.toView([g.x, g.y]), moved: false, dragging: false, turns: 0, mode: "stretch", copy: false, action: null, actionTitle: null, items: [], point: null, snap: null };
    return true;
  }
  get hotGripState() { return this.hot ? { mode: this.hot.mode, copy: this.hot.copy, dragging: this.hot.dragging, turns: this.hot.turns, action: this.hot.action } : null; }
  private async gripMenu(g: Grip, at: V2): Promise<boolean> {
    const acts: any[] = (await this.app.tryCall("grips.actions", { id: g.id, index: g.index })) ?? [];
    if (!Array.isArray(acts) || acts.length <= 1) return false;
    showMenu(acts.map((a) => ({
      title: a.title, action: async () => {
        if (a.immediate) { await this.app.tryCall("grips.edit", { id: g.id, index: g.index, x: g.x, y: g.y, action: a.action }); await this.app.refresh(["drawing", "selection", "properties", "history"]); return; }
        this.hot = { grip: g, origin: [g.x, g.y], startView: this.toView([g.x, g.y]), moved: false, dragging: false, turns: 0, mode: "stretch", copy: false,
          action: a.action === "stretch" ? null : a.action, actionTitle: a.title, items: [], point: null, snap: null };
        this.setHint(`${a.title}: click the new location · Esc cancels`);
        this.sendGripPreview();
      },
    })), { x: at[0], y: at[1] });
    return true;
  }

  // ---- local modes, keyboard ----
  /** Esc: ends a window, a hot grip, a zoom window, a placement or the marking menu first (CanvasView.cancelLocalModes). */
  cancelLocalModes(): boolean {
    let any = false;
    if (this.win) { this.win = null; any = true; }
    if (this.hot) { this.hot = null; any = true; }
    if (this.zoomWindowPending) { this.zoomWindowPending = false; any = true; }
    if (this.placement) { this.placement = null; this.setHint(""); any = true; }
    if (this.radial) { this.radial.view?.el.remove(); this.radial = null; any = true; }
    if (this.dynInput) { this.dynInput = null; any = true; }
    if (this.vpDrag) { this.vpDrag = null; any = true; }
    if (any) { this.overlayDirty = true; this.schedule(); }
    return any;
  }
  cancelGrip() { return this.cancelLocalModes(); }
  get view() { return this.v; }
  private get cmdInput(): HTMLInputElement | null { return document.querySelector(".cmd-input input"); }
  private keyDown(e: KeyboardEvent) {
    if (!this.interactive || !this.el.isConnected || InPlaceTextEditor.current) return;
    const t = e.target as HTMLElement | null;
    const cmd = this.cmdInput;
    const inOther = !!t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT" || t.isContentEditable) && t !== cmd;
    if (inOther || e.ctrlKey || e.metaKey || e.altKey) return;
    if (document.querySelector(".dlg-overlay, .overlay")) return;
    const typed = cmd?.value ?? "";
    const stop = () => { e.preventDefault(); e.stopImmediatePropagation(); if (e.key === " ") this.swallowSpaceUp = true; this.overlayDirty = true; this.schedule(); };
    if (this.paper) {
      if ((e.key === "Delete" || e.key === "Backspace") && this.selectedViewport !== null && !typed) {
        const vp = this.viewports.find((x) => x.index === this.selectedViewport);
        if (vp?.locked) this.app.print("The viewport is locked."); else void this.sheetViewportOp(this.selectedViewport, "remove");
        stop(); return;
      }
      if ((e.key === "f" || e.key === "F") && !typed && t !== cmd) { this.fitPaper(); stop(); return; }
      return;
    }
    if (e.key === " " && !e.repeat && !typed) {
      if (this.placement) {
        this.placement.turns += e.shiftKey ? -1 : 1;
        this.setHint(`Rotation ${(((this.placement.turns % 4) + 4) % 4) * 90}° · click to place · Esc cancels`);
        this.sendPlacementPreview(); stop(); return;
      }
      if (this.hot && !this.hot.dragging && !this.hot.action) { this.handleGripInput(""); stop(); return; }
      if (this.hot && this.hot.dragging) {
        this.hot.turns += e.shiftKey ? -1 : 1; this.hot.moved = true;
        this.setHint(`Rotated ${(((this.hot.turns % 4) + 4) % 4) * 90}° about the grip`);
        this.sendGripPreview(); stop(); return;
      }
    }
    if (e.key === "Tab") {
      // Dynamic input: Tab moves between the Length and Angle (or X and Y) fields.
      const req = this.app.prompt;
      if (req.active && req.kinds.includes("point") && this.app.sysvarOn("DYNMODE")) {
        const di = this.dynInput ?? { field: 0 as 0 | 1, values: ["", ""] as [string, string] };
        if (typed.trim()) di.values[di.field] = typed.trim();
        di.field = di.field === 0 ? 1 : 0;
        this.dynInput = di;
        if (cmd) { cmd.value = ""; cmd.dispatchEvent(new Event("input")); }
        this.app.commandInput = "";
        stop(); return;
      }
      if (this.app.isIdle && !typed && this.hover?.id) {
        const id = Number(this.hover.id);
        void this.app.tryCall("select.chain", { id, pixelsPerUnit: this.v.scale }).then((r) => { if (r?.chain?.length) this.setHint(r.hint); this.app.refresh(["selection", "properties"]); });
        stop(); return;
      }
      return;
    }
    if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(e.key) && this.app.isIdle && !typed && this.app.selection.ids.length && t !== cmd) {
      // Arrow keys nudge the selection (MOD-028): one pixel, the snap spacing with grid snap, ×10 with Shift.
      const d = e.key === "ArrowLeft" ? [-1, 0] : e.key === "ArrowRight" ? [1, 0] : e.key === "ArrowDown" ? [0, -1] : [0, 1];
      const c = Math.cos(-this.tw), s = Math.sin(-this.tw);
      void this.app.tryCall("select.nudge", { dx: d[0] * c - d[1] * s, dy: d[0] * s + d[1] * c, big: e.shiftKey }).then((r) => { if (r) this.setHint(r.hint); this.app.refresh(["drawing", "history"]); });
      stop(); return;
    }
  }
  /** Token of the dynamic-input fields (core dynamicInputToken): "@L<A", "L" (direct distance), "@x,y" / "#x,y". */
  private dynToken(fromClick = false): string | null {
    const di = this.dynInput;
    if (!di) return null;
    const vals: [string, string] = [...di.values] as [string, string];
    const typed = this.app.commandInput.trim();
    if (typed) vals[di.field] = typed;
    if (fromClick && !vals[0] && !vals[1]) return null;
    this.dynInput = null;
    const base = this.promptBase();
    if (base || this.dyn?.length !== undefined) {
      const len = vals[0] || (this.dyn?.length !== undefined ? fmt(this.dyn.length, 6) : "");
      if (!len) return null;
      return vals[1] ? `@${len}<${vals[1].replace(/°$/, "")}` : len;
    }
    const x = vals[0] || fmt(this.cursorPoint()[0], 6), y = vals[1] || fmt(this.cursorPoint()[1], 6);
    return `${x},${y}`;
  }

  // ---- right button: Enter, snap overrides, grip menus, marking menu, shortcut menu ----
  private rightDown(v: V2, e: MouseEvent) {
    if (this.paper) { const vp = this.viewportAt(v); if (vp) { this.selectedViewport = vp.index; this.contentDirty = true; this.schedule(); this.sheetMenu(vp, [e.clientX, e.clientY]); } return; }
    if (this.cancelLocalModes()) return;
    const app = this.app, req = app.prompt;
    // Shift+right-click at a point prompt: one-shot object snap override menu (PRC-019).
    if (e.shiftKey && req.active && req.kinds.includes("point")) {
      const items: MenuItem[] = SNAP_OVERRIDES.map(([title, token]) => (title === null ? { separator: true } : { title, action: () => app.submitLine(token) }));
      showMenu(items, { x: e.clientX, y: e.clientY });
      return;
    }
    if (!app.isIdle || app.commandInput) { this.enterPressed(); return; }
    const hg = this.hoverGrip;
    if (hg) { void this.gripMenu(hg, [e.clientX, e.clientY]).then((shown) => { if (!shown) this.openRadialOrMenu(v, e); }); return; }
    this.openRadialOrMenu(v, e);
  }
  private openRadialOrMenu(v: V2, e: MouseEvent) {
    // Marking menu (APP-022): wait for a drag; a plain right-click still shows the shortcut menu on release.
    if (radialPrefs.enabled && e.buttons & 2) {
      const r = { origin: v, client: [e.clientX, e.clientY] as V2, view: null, context: null as string | null };
      this.radial = r;
      void this.app.tryCall("canvas.state").then((st) => { if (st?.radialContext) r.context = st.radialContext; });
      return;
    }
    void this.contextMenu([e.clientX, e.clientY]);
  }
  private radialDrag(v: V2, e: MouseEvent) {
    const r = this.radial!;
    const s = radialSector(v[0] - r.origin[0], v[1] - r.origin[1]);
    if (!r.view && s !== null) {
      const ctx = (r.context as any) ?? radialContext(this.app.selection.ids, () => false);
      r.view = new RadialMenuView(radialItems(ctx), r.origin[0], r.origin[1]);
      this.el.append(r.view.el);
    }
    r.view?.setHighlighted(s);
    if (s !== null && r.view) this.app.live.snapHint = radialTooltip(r.view.items[s], (n) => this.app.lookup(n) as any);
    this.app.emit("live");
    void e;
  }
  private rightUp(_v: V2, e: MouseEvent) {
    const r = this.radial;
    if (!r) return;
    this.radial = null;
    if (r.view) {
      const chosen = r.view.highlighted !== null ? r.view.items[r.view.highlighted] : null;
      r.view.el.remove();
      this.app.live.snapHint = this.hint; this.app.emit("live");
      if (chosen) void this.app.runCommand(chosen.command);
      return;
    }
    void this.contextMenu([e.clientX, e.clientY]);
  }
  /** Right-click shortcut menu (ShortcutMenu.items, APP-023). */
  private async contextMenu(at: V2) {
    const app = this.app;
    const st = (await app.tryCall("canvas.state")) ?? this.state;
    const items = shortcutItems({ hasSelection: app.selection.ids.length > 0, lastCommand: st.lastCommand ?? null, recentInput: app.inputHistory,
      canUndo: !!st.canUndo, canRedo: !!st.canRedo, undoLabel: st.undoLabel ?? null, redoLabel: st.redoLabel ?? null });
    showMenu(items.map((it) => this.menuItem(it)), { x: at[0], y: at[1] });
  }
  private menuItem(it: ShortcutItem): MenuItem {
    const a = it.action, app = this.app;
    if (a.kind === "separator") return { separator: true };
    if (a.kind === "submenu") return { title: it.title, disabled: !it.enabled, submenu: a.items.map((x) => this.menuItem(x)) };
    const run = () => {
      switch (a.kind) {
        case "run": return app.runCommand(a.line);
        case "repeatLast": return app.tryCall("canvas.state").then((s) => s?.lastCommand && app.runCommand(s.lastCommand));
        case "undo": return app.undo();
        case "redo": return app.redo();
        case "deselect": return app.tryCall("select.set", { ids: [] }).then(() => app.refresh(["selection", "properties"]));
        case "selectAll": return app.selectAll();
        case "zoomExtents": return this.zoomExtents();
        case "properties": return app.action("@panel:Properties");
        case "quickProperties": return app.action("@panel:Quick Props");
      }
    };
    return { title: it.title, disabled: !it.enabled, action: () => void run() };
  }
  /** Enter pressed (AppModel.enterPressed): submits what is typed, or answers the prompt with Enter. */
  private enterPressed() {
    const cmd = this.cmdInput;
    const text = cmd?.value ?? this.app.commandInput;
    if (cmd) { cmd.value = ""; }
    this.app.commandInput = "";
    void this.app.submitLine(text);
  }

  // ---- double-click editing (CanvasView.editObject) ----
  async editObject(id: number) {
    const app = this.app;
    const r = await app.tryCall("canvas.doubleClick", { id });
    if (!r) return;
    if (r.action === "textEditor") {
      const t = r.text ?? {};
      new InPlaceTextEditor(app, { id, content: String(r.content ?? ""), singleLine: !!r.singleLine, styleFont: String(r.styleFont ?? "Helvetica"), color: String(r.color ?? "ByLayer"), format: r.format ?? {},
        text: { position: Array.isArray(t.position) ? [t.position[0], t.position[1]] : [0, 0], height: Number(t.height ?? 2.5), rotation: Number(t.rotation ?? 0), halign: String(t.halign ?? "left"), width: Number(t.width ?? 0) } },
        this.el, (p) => this.toView(p), this.v.scale, () => { this.focus(); this.refresh(); });
      return;
    }
    if (r.action === "textDialog") {
      const v = await editTextAlert(String(r.message ?? "Edit the text content."), String(r.content ?? ""), !!r.multiline);
      if (v !== null && v !== r.content) { await app.tryCall("text.edit", { id, content: v }); await app.refresh(["drawing", "properties", "history"]); }
      this.focus();
      return;
    }
    await app.refresh(["selection", "properties"]);
    await app.action("@panel:Properties");
  }

  // ---- temporary dimensions ----
  private editTempDim(td: TempDim, v: V2) {
    const inp = document.createElement("input");
    inp.className = "tempdim-edit";
    inp.value = td.text;
    Object.assign(inp.style, { left: v[0] - 40 + "px", top: v[1] - 11 + "px" });
    this.el.append(inp);
    inp.focus(); inp.select();
    let done = false;
    const finish = async (ok: boolean) => {
      if (done) return; done = true;
      inp.remove();
      if (ok && inp.value.trim() && inp.value.trim() !== td.text) {
        await this.app.tryCall("tempdims.set", { id: td.id, index: td.index, value: inp.value.trim() });
        await this.app.refresh(["drawing", "selection", "properties", "history"]);
      }
      this.focus();
    };
    inp.addEventListener("keydown", (e) => { e.stopPropagation(); if (e.key === "Enter") void finish(true); else if (e.key === "Escape") void finish(false); });
    inp.addEventListener("blur", () => void finish(true));
  }

  // ---- tool palette placement (MOD-029) and drops ----
  startPlacement(item: string, title = "") {
    if (!item) return;
    this.app.closeStart?.();
    if (this.app.prompt.active) void this.app.cancel();
    this.placement = { item, title, turns: 0, items: [] };
    this.setHint(`Click in the drawing to place ${title || "the item"} · Space rotates 90° · Shift-click keeps placing · Esc cancels`);
    this.focus();
    if (this.mouse) this.sendPlacementPreview();
  }
  get placementState() { return this.placement ? { item: this.placement.item, turns: this.placement.turns } : null; }
  private async placeAt(w: V2, keep: boolean) {
    const pl = this.placement!;
    const hit = pick(this.entries, w, 6 / this.v.scale);
    const r = await this.app.tryCall("place.drop", { item: pl.item, x: w[0], y: w[1], turns: pl.turns, hit: hit?.id ? Number(hit.id) : undefined });
    if (r?.ok && !keep) { this.placement = null; this.setHint(""); }
    await this.app.refresh(["drawing", "selection", "properties", "history"]);
  }
  private async drop(e: DragEvent, v: V2) {
    const dt = e.dataTransfer;
    if (!dt) return;
    const w = this.toWorld(v[0], v[1]);
    if (dt.files?.length) {
      e.preventDefault();
      const bridge = (window as any).archiDrop as { pathForFile?(f: File): string } | undefined;
      const paths = [...dt.files].map((f) => bridge?.pathForFile?.(f) || (f as any).path || f.name).filter(Boolean);
      const r = await this.app.tryCall("file.drop", { paths, x: w[0], y: w[1] });
      if (!r) return;
      for (const p of r.open ?? []) await this.app.open(p);
      for (const p of r.scripts ?? []) await this.app.action("@runScript:" + p);
      await this.app.refresh(["drawing", "selection", "properties", "history"]);
      this.focus();
      return;
    }
    const s = dt.getData(DROP_TYPE);
    if (!s || !Object.values(PREFIX).some((p) => s.startsWith(p))) return;
    e.preventDefault();
    const hit = pick(this.entries, w, 6 / this.v.scale);
    const r = await this.app.tryCall("place.drop", { item: s, x: w[0], y: w[1], hit: hit?.id ? Number(hit.id) : undefined });
    if (r?.prompt) this.app.setPrompt(r.prompt);
    await this.app.refresh(["drawing", "selection", "properties", "history"]);
    this.focus();
  }

  // ---- app hooks: grip input and dynamic-input fields take the command line's Enter (AppModel.gripInput) ----
  private hookApp() {
    const app = this.app;
    const submit = app.submitLine.bind(app);
    app.submitLine = async (text: string) => {
      if (this.el.isConnected && !this.paper && this.handleGripInput(text)) return;
      const req = app.prompt;
      if (this.dynInput && req.active && req.kinds.includes("point")) {
        const di = this.dynInput;
        if (text.trim()) di.values[di.field] = text.trim();
        app.commandInput = "";
        const tok = this.dynToken();
        if (tok) return submit(tok);
      }
      return submit(text);
    };
    const cancel = app.cancel.bind(app);
    app.cancel = async () => { if (this.cancelLocalModes()) return; return cancel(); };
    // Host actions of the portable canvas commands (VPMAX / VPMIN, TOOLPALETTESCLOSE, RADIALMENU).
    const prev = app.uiHooks.host;
    app.uiHooks.host = (p: any) => {
      switch (p?.action) {
        case "maximizeViewport": {
          app.activeLayout = 0; app.setUI("mode", "2D");
          if (Array.isArray(p.rect)) setTimeout(() => this.zoomTo(p.rect), 60);
          return true;
        }
        case "restoreViewport": app.activeLayout = Number(p.layout ?? 0) + 1; app.setUI("mode", "Sheet"); return true;
        case "hidePanel": if (app.panelTab === p.panel) app.setUI("panelTab", "Properties"); return true;
        case "preference": if (p.key === "radialMenu") { radialPrefs.enabled = !!p.value; return true; } break;
      }
      return !!prev?.(p);
    };
  }
}
