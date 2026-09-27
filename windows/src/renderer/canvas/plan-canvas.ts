// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The 2D drafting canvas (PlanCanvasView in CanvasView.swift): paints the engine's DrawList with the Mac colours,
// grid and axes, UCS icon, selection highlight and grips; overlay with hover highlight, rubber-band preview from the
// prompt, window/crossing selection, snap markers, crosshair with pick box and dynamic input. Pan with the middle
// button or Space+drag, zoom with the wheel, double middle click for extents.
import type { App } from "../app";
import { snapPoint, type Grip, type SnapInfo } from "../../shared/protocol";
import { decodeDrawList, decodeItem, paintItems, applyView, Entry, Item, View, Params, defaultParams, pick, setImageLoadedCallback, setImageUrlResolver } from "./drawitems";

const ACCENT = "#F5C518";
const MM_PER_UNIT: Record<string, number> = { millimeters: 1, centimeters: 10, meters: 1000, inches: 25.4, feet: 304.8 };
type WindowSel = { start: [number, number]; current: [number, number]; moved: boolean; purpose: "select" | "request" | "zoom"; shift: boolean };
type HotGrip = { grip: Grip; dragging: boolean; moved: boolean };

export class PlanCanvas {
  el: HTMLElement;
  private content: HTMLCanvasElement;
  private overlay: HTMLCanvasElement;
  private v: View = { cx: 12000, cy: 7000, scale: 0.04, w: 800, h: 600 };
  private dpr = 1;
  private entries: Entry[] = [];
  private byId = new Map<string, Entry>();
  private grips: Grip[] = [];
  private mouse: [number, number] | null = null;
  private world: [number, number] = [0, 0];
  private hover: Entry | null = null;
  private hoverGrip: Grip | null = null;
  private hot: HotGrip | null = null;
  private preview: Item[] = [];
  private snap: SnapInfo | null = null;
  private win: WindowSel | null = null;
  private panLast: [number, number] | null = null;
  private spaceDown = false;
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
  private paper: { w: number; h: number } | null = null;
  private lastLayout = "";
  private viewports: { rect: number[]; title?: string }[] = [];

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
    setImageLoadedCallback(() => { this.contentDirty = true; this.schedule(); });
    if (app.engine.native) setImageUrlResolver((p) => app.engine.native!.fileUrl(p));
    app.on(["drawing", "layers"], () => this.loadDrawList());
    app.on("selection", () => this.loadGrips());
    app.on("sysvars", () => { this.contentDirty = true; this.schedule(); });
    app.on("prompt", () => { if (!app.prompt.active) { this.preview = []; this.snap = null; } else this.preview = (app.prompt.preview ?? []).map(decodeItem).filter(Boolean) as Item[]; this.overlayDirty = true; this.schedule(); });
    app.on("ui", () => this.loadDrawList());
    app.on("live", () => { this.overlayDirty = true; this.schedule(); });
    this.bind();
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
    const paper = res?.paper && typeof res.paper.width === "number" ? { w: Number(res.paper.width), h: Number(res.paper.height) } : null;
    const layoutKey = params.layout ?? "";
    this.paper = paper;
    this.viewports = Array.isArray(res?.viewports) ? res.viewports.filter((v: any) => Array.isArray(v.rect)) : [];
    if (layoutKey !== this.lastLayout) { this.lastLayout = layoutKey; if (paper) this.zoomTo([-10, -10, paper.w + 10, paper.h + 10]); else if (this.entries.length) this.zoomExtents(); }
    this.byId = new Map(this.entries.filter((e) => e.id).map((e) => [e.id!, e]));
    if (this.needsInitialZoom && this.entries.length && !params.layout) { this.needsInitialZoom = false; this.zoomExtents(); }
    this.contentDirty = true; this.schedule();
  }
  async loadGrips() {
    const app = this.app;
    this.grips = app.selection.ids.length && app.selection.ids.length <= 300 && app.isIdle ? (await app.tryCall("grips.get")) ?? [] : [];
    if (!Array.isArray(this.grips)) this.grips = (this.grips as any)?.grips ?? [];
    this.contentDirty = true; this.schedule();
  }

  // ---- view ----
  private resize() {
    const r = this.el.getBoundingClientRect();
    this.dpr = window.devicePixelRatio || 1;
    this.v.w = Math.max(1, r.width); this.v.h = Math.max(1, r.height);
    for (const c of [this.content, this.overlay]) { c.width = Math.round(this.v.w * this.dpr); c.height = Math.round(this.v.h * this.dpr); }
    this.contentDirty = this.overlayDirty = true;
    this.paintNow();
  }
  toWorld(x: number, y: number): [number, number] { return [(x - this.v.w / 2) / this.v.scale + this.v.cx, (this.v.h / 2 - y) / this.v.scale + this.v.cy]; }
  toView(p: [number, number]): [number, number] { return [(p[0] - this.v.cx) * this.v.scale + this.v.w / 2, this.v.h / 2 - (p[1] - this.v.cy) * this.v.scale]; }
  zoomExtents() {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const e of this.entries) { if (!isFinite(e.bounds[0])) continue; x0 = Math.min(x0, e.bounds[0]); y0 = Math.min(y0, e.bounds[1]); x1 = Math.max(x1, e.bounds[2]); y1 = Math.max(y1, e.bounds[3]); }
    if (!isFinite(x0)) { const ex = this.app.info?.extents; if (ex) [x0, y0, x1, y1] = ex; else return; }
    this.zoomTo([x0, y0, x1, y1]);
  }
  zoomTo(b: [number, number, number, number]) {
    const w = Math.max(b[2] - b[0], 1e-6), hh = Math.max(b[3] - b[1], 1e-6);
    this.v.scale = Math.min(this.v.w / w, this.v.h / hh) * 0.9;
    this.v.cx = (b[0] + b[2]) / 2; this.v.cy = (b[1] + b[3]) / 2;
    this.viewChanged();
  }
  zoomBy(f: number, at?: [number, number]) {
    const p = at ?? [this.v.w / 2, this.v.h / 2];
    const before = this.toWorld(p[0], p[1]);
    this.v.scale = Math.min(1e4, Math.max(1e-7, this.v.scale * f));
    const after = this.toWorld(p[0], p[1]);
    this.v.cx += before[0] - after[0]; this.v.cy += before[1] - after[1];
    this.viewChanged();
  }
  zoomWindow() { this.zoomWindowPending = true; this.focus(); }
  private viewChanged() {
    const units = this.app.info?.units ?? "millimeters";
    this.app.live.zoomPercent = (this.v.scale / ((72 / 25.4) * (MM_PER_UNIT[units] ?? 1))) * 100;
    this.app.emit("live");
    this.contentDirty = this.overlayDirty = true; this.schedule();
    if (this.requestedScale && (this.v.scale / this.requestedScale > 4 || this.requestedScale / this.v.scale > 4)) { clearTimeout((this as any)._rq); (this as any)._rq = setTimeout(() => this.loadDrawList(), 250); }
  }
  focus() { this.overlay.focus({ preventScroll: true }); }
  refresh() { this.contentDirty = this.overlayDirty = true; this.schedule(); }

  private frame = 0;
  private schedule() { if (!this.frame) this.frame = requestAnimationFrame(() => { this.frame = 0; this.paintNow(); }); }
  paintNow() {
    if (this.contentDirty) { this.paintContent(); this.contentDirty = false; }
    this.paintOverlay(); this.overlayDirty = false;
  }
  private params(): Params { return { ...defaultParams, lineweights: this.app.sysvarOn("LWDISPLAY") }; }

  // ---- content ----
  private paintContent() {
    const ctx = this.content.getContext("2d")!;
    const { w, h } = this.v, d = this.dpr;
    ctx.setTransform(d, 0, 0, d, 0, 0);
    ctx.fillStyle = "#1E1F22"; ctx.fillRect(0, 0, w, h);
    if (this.paper) {
      // Sheet (paper space): grey backdrop, white paper with a soft shadow, drawn in paper millimetres.
      ctx.fillStyle = "#3A3B40"; ctx.fillRect(0, 0, w, h);
      const a = this.toView([0, this.paper.h]), b = this.toView([this.paper.w, 0]);
      ctx.shadowColor = "rgba(0,0,0,0.5)"; ctx.shadowBlur = 16; ctx.shadowOffsetY = 4;
      ctx.fillStyle = "#FFFFFF"; ctx.fillRect(a[0], a[1], b[0] - a[0], b[1] - a[1]);
      ctx.shadowColor = "transparent"; ctx.shadowBlur = 0; ctx.shadowOffsetY = 0;
      ctx.strokeStyle = "rgba(0,0,0,0.35)"; ctx.lineWidth = 1;
      for (const vp of this.viewports) { const p0 = this.toView([vp.rect[0], vp.rect[3]]), p1 = this.toView([vp.rect[2], vp.rect[1]]); ctx.strokeRect(Math.round(p0[0]) + 0.5, Math.round(p0[1]) + 0.5, Math.round(p1[0] - p0[0]), Math.round(p1[1] - p0[1])); }
    } else if (this.app.sysvarOn("GRIDMODE")) this.paintGrid(ctx); else this.paintAxes(ctx);
    // Visible entries only.
    const [vx0, vy1] = this.toWorld(0, 0), [vx1, vy0] = this.toWorld(w, h);
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
    const [x0w, y1w] = this.toWorld(0, 0), [x1w, y0w] = this.toWorld(this.v.w, this.v.h);
    const i0 = Math.floor(x0w / minor), i1 = Math.ceil(x1w / minor), j0 = Math.floor(y0w / minor), j1 = Math.ceil(y1w / minor);
    if (i1 - i0 > 2000 || j1 - j0 > 2000) return;
    const mn = new Path2D(), mj = new Path2D();
    for (let i = i0; i <= i1; i++) {
      const wx = i * minor, x = Math.round((wx - this.v.cx) * s + this.v.w / 2) + 0.5;
      const isMajor = Math.abs(wx / major - Math.round(wx / major)) < 1e-6;
      (isMajor ? mj : mn).moveTo(x, 0); (isMajor ? mj : mn).lineTo(x, this.v.h);
    }
    for (let j = j0; j <= j1; j++) {
      const wy = j * minor, y = Math.round(this.v.h / 2 - (wy - this.v.cy) * s) + 0.5;
      const isMajor = Math.abs(wy / major - Math.round(wy / major)) < 1e-6;
      (isMajor ? mj : mn).moveTo(0, y); (isMajor ? mj : mn).lineTo(this.v.w, y);
    }
    ctx.lineWidth = 1;
    ctx.strokeStyle = "rgba(255,255,255,0.035)"; ctx.stroke(mn);
    ctx.strokeStyle = "rgba(255,255,255,0.075)"; ctx.stroke(mj);
    this.paintAxes(ctx);
  }
  private paintUCS(ctx: CanvasRenderingContext2D) {
    const o: [number, number] = [26, this.v.h - 26], len = 34;
    const arrow = (dx: number, dy: number, col: string) => {
      ctx.strokeStyle = col; ctx.fillStyle = col; ctx.lineWidth = 1.5;
      const tip: [number, number] = [o[0] + dx * len, o[1] + dy * len], back: [number, number] = [o[0] + dx * (len - 6), o[1] + dy * (len - 6)], n = [-dy, dx];
      ctx.beginPath(); ctx.moveTo(o[0], o[1]); ctx.lineTo(tip[0], tip[1]); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(tip[0], tip[1]); ctx.lineTo(back[0] + n[0] * 3, back[1] + n[1] * 3); ctx.lineTo(back[0] - n[0] * 3, back[1] - n[1] * 3); ctx.closePath(); ctx.fill();
    };
    arrow(1, 0, "rgba(230,89,89,0.9)"); arrow(0, -1, "rgba(89,217,115,0.9)");
    ctx.strokeStyle = "rgba(217,217,217,0.9)"; ctx.lineWidth = 1; ctx.strokeRect(o[0] - 3, o[1] - 3, 6, 6);
    ctx.fillStyle = "rgba(217,217,217,0.9)"; ctx.font = "600 9px " + getComputedStyle(document.body).getPropertyValue("--ui");
    ctx.fillText("X", o[0] + len + 5, o[1] + 3); ctx.fillText("Y", o[0] - 3, o[1] - len - 5); ctx.fillText("W", o[0] + 6, o[1] - 5);
  }
  private paintGrips(ctx: CanvasRenderingContext2D) {
    if (!this.app.isIdle) return;
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

  // ---- overlay ----
  private paintOverlay() {
    const ctx = this.overlay.getContext("2d")!;
    const d = this.dpr;
    ctx.setTransform(d, 0, 0, d, 0, 0);
    ctx.clearRect(0, 0, this.v.w, this.v.h);
    const prm = this.params();
    applyView(ctx, this.v, d);
    if (this.hover && !this.app.selection.ids.includes(this.hover.id!)) paintItems(ctx, this.hover.items, this.v, prm, { colorOverride: "rgba(255,255,255,0.85)", extraWidth: 1.6, fillAlpha: 0.06, noText: false });
    if (this.app.prompt.active && this.preview.length && this.mouse) paintItems(ctx, this.preview, this.v, prm);
    ctx.setTransform(d, 0, 0, d, 0, 0);
    // Rubber band from the base point.
    const base = this.hot ? ([this.hot.grip.x, this.hot.grip.y] as [number, number]) : this.promptBase();
    if (this.mouse && !this.win && base) {
      const a = this.toView(base), b = this.toView(this.cursorPoint());
      ctx.strokeStyle = "rgba(255,255,255,0.45)"; ctx.lineWidth = 1; ctx.setLineDash([5, 4]);
      ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke(); ctx.setLineDash([]);
    }
    if (this.win && this.win.moved) {
      const w = this.win, x = Math.min(w.start[0], w.current[0]), y = Math.min(w.start[1], w.current[1]);
      const ww = Math.abs(w.current[0] - w.start[0]), hh = Math.abs(w.current[1] - w.start[1]);
      const crossing = w.current[0] < w.start[0];
      const c = w.purpose === "zoom" ? [204, 204, 204] : crossing ? [64, 204, 102] : [77, 128, 255];
      ctx.fillStyle = `rgba(${c},0.13)`; ctx.fillRect(x, y, ww, hh);
      ctx.strokeStyle = `rgb(${c})`; ctx.lineWidth = 1; if (crossing && w.purpose !== "zoom") ctx.setLineDash([5, 3]);
      ctx.strokeRect(x + 0.5, y + 0.5, ww - 1, hh - 1); ctx.setLineDash([]);
    }
    if (this.hoverGrip && !this.hot) this.gripMark(ctx, this.toView([this.hoverGrip.x, this.hoverGrip.y]), "rgb(255,115,140)");
    if (this.hot) this.gripMark(ctx, this.toView([this.hot.grip.x, this.hot.grip.y]), "rgb(230,51,51)");
    if (this.snap && this.mouse) this.snapMarker(ctx, this.snap);
    if (this.mouse && !this.panLast && this.interactive) {
      const req = this.app.prompt;
      const pickbox = (this.app.isIdle && !this.hot) || (req.active && req.kinds.some((k) => k === "selection" || k === "entity") && !req.kinds.includes("point"));
      this.crosshair(ctx, this.mouse, pickbox);
      if (this.app.sysvarOn("DYNMODE")) this.dynamicInput(ctx, this.mouse);
    }
  }
  private promptBase(): [number, number] | null {
    const p = this.app.prompt;
    if (!p.active || !p.base) return null;
    const b: any = p.base;
    return Array.isArray(b) ? [b[0], b[1]] : [b.x, b.y];
  }
  private engineCursor: [number, number] | null = null;
  private cursorPoint(): [number, number] { return this.snap ? snapPoint(this.snap) : this.engineCursor ?? this.world; }
  private gripMark(ctx: CanvasRenderingContext2D, v: [number, number], col: string) {
    const sz = 8, r = [Math.round(v[0] - sz / 2) + 0.5, Math.round(v[1] - sz / 2) + 0.5];
    ctx.fillStyle = col; ctx.fillRect(r[0], r[1], sz, sz); ctx.strokeStyle = "rgba(255,255,255,0.9)"; ctx.lineWidth = 1; ctx.strokeRect(r[0], r[1], sz, sz);
  }
  private crosshair(ctx: CanvasRenderingContext2D, v: [number, number], pickbox: boolean) {
    const pct = 10;
    const arm = Math.max(8, (pct / 200) * Math.max(this.v.w, this.v.h));
    const x = Math.round(v[0]) + 0.5, y = Math.round(v[1]) + 0.5, gap = pickbox ? 5 : 0;
    ctx.lineWidth = 1; ctx.strokeStyle = "rgba(242,242,242,0.95)";
    ctx.beginPath();
    ctx.moveTo(x - arm, y); ctx.lineTo(x - gap, y); ctx.moveTo(x + gap, y); ctx.lineTo(x + arm, y);
    ctx.moveTo(x, y - arm); ctx.lineTo(x, y - gap); ctx.moveTo(x, y + gap); ctx.lineTo(x, y + arm);
    ctx.stroke();
    if (pickbox) ctx.strokeRect(x - 5, y - 5, 10, 10);
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
    const label = sn.kind.charAt(0).toUpperCase() + sn.kind.slice(1);
    this.tooltip(ctx, [label], [cx + 10, cy + 12], true);
  }
  /** Small dark tooltip box; `at` is its top-left corner (screen, y down). */
  private tooltip(ctx: CanvasRenderingContext2D, lines: string[], at: [number, number], accent = false) {
    if (!lines.length) return;
    ctx.font = `10.5px ${getComputedStyle(document.body).getPropertyValue("--mono")}`;
    const w = Math.max(...lines.map((l) => ctx.measureText(l).width)) + 12, lh = 14, hh = lines.length * lh + 6;
    let x = at[0], y = at[1];
    if (x + w > this.v.w - 4) x = this.v.w - w - 4;
    if (y + hh > this.v.h - 4) y = at[1] - hh - 24;
    ctx.beginPath(); (ctx as any).roundRect ? (ctx as any).roundRect(x, y, w, hh, 3) : ctx.rect(x, y, w, hh);
    ctx.fillStyle = "rgba(43,44,49,0.96)"; ctx.fill();
    ctx.strokeStyle = accent ? "rgba(245,197,24,0.6)" : "rgba(255,255,255,0.14)"; ctx.lineWidth = 1; ctx.stroke();
    ctx.fillStyle = accent ? ACCENT : "#E6E6E6"; ctx.textBaseline = "alphabetic";
    lines.forEach((l, i) => ctx.fillText(l, x + 6, y + 3 + (i + 1) * lh - 3));
  }
  private dynamicInput(ctx: CanvasRenderingContext2D, v: [number, number]) {
    const req = this.app.prompt, lines: string[] = [];
    const cp = this.cursorPoint();
    if (req.active) {
      lines.push((req.label ?? req.message.replace(/\s*\[[^\]]*\]/, "").replace(/:\s*$/, "")) + (req.keywords.length ? "  [" + req.keywords.join("/") + "]" : ""));
      if (req.kinds.some((k) => k === "point" || k === "distance" || k === "angle")) {
        const b = this.promptBase();
        if (b) { const dx = cp[0] - b[0], dy = cp[1] - b[1]; let a = (Math.atan2(dy, dx) * 180) / Math.PI; if (a < 0) a += 360; lines.push(`L ${Math.hypot(dx, dy).toFixed(2)}   ∠ ${a.toFixed(1)}°`); }
        else lines.push(`X ${cp[0].toFixed(2)}   Y ${cp[1].toFixed(2)}`);
      }
    } else if (this.hot) {
      const dx = cp[0] - this.hot.grip.x, dy = cp[1] - this.hot.grip.y; let a = (Math.atan2(dy, dx) * 180) / Math.PI; if (a < 0) a += 360;
      lines.push("Stretch point  (Space rotates 90°)", `L ${Math.hypot(dx, dy).toFixed(2)}   ∠ ${a.toFixed(1)}°`);
    }
    if (this.app.commandInput) lines.push("› " + this.app.commandInput);
    if (lines.length) this.tooltip(ctx, lines, [v[0] + 20, v[1] + 18]);
  }

  // ---- input ----
  private bind() {
    const o = this.overlay;
    const pos = (e: MouseEvent): [number, number] => { const r = o.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
    o.addEventListener("contextmenu", (e) => e.preventDefault());
    o.addEventListener("mouseleave", () => { this.mouse = null; this.hover = null; this.hoverGrip = null; this.snap = null; this.app.live.snapHint = ""; this.overlayDirty = true; this.schedule(); });
    o.addEventListener("mousemove", (e) => this.move(pos(e), e));
    o.addEventListener("mousedown", (e) => this.down(pos(e), e));
    addEventListener("mouseup", (e) => this.up(pos(e), e));
    o.addEventListener("wheel", (e) => { e.preventDefault(); const p = pos(e); const f = Math.exp(-e.deltaY * (e.deltaMode === 1 ? 0.05 : 0.0015)); this.zoomBy(f, p); this.move(p, e as any); }, { passive: false });
    o.addEventListener("keydown", (e) => { if (e.code === "Space" && this.app.commandInput === "" && !e.repeat) { this.spaceDown = true; } });
    o.addEventListener("keyup", (e) => { if (e.code === "Space") this.spaceDown = false; });
  }
  private gripAt(v: [number, number]) {
    for (const g of this.grips) { const p = this.toView([g.x, g.y]); if (Math.abs(p[0] - v[0]) <= 5 && Math.abs(p[1] - v[1]) <= 5) return g; }
    return null;
  }
  private move(v: [number, number], e: MouseEvent) {
    this.mouse = v;
    if (this.panLast) {
      this.v.cx -= (v[0] - this.panLast[0]) / this.v.scale; this.v.cy += (v[1] - this.panLast[1]) / this.v.scale;
      this.panLast = v; this.viewChanged(); return;
    }
    this.world = this.toWorld(v[0], v[1]);
    if (this.win) { this.win.current = v; if (Math.hypot(v[0] - this.win.start[0], v[1] - this.win.start[1]) > 3) this.win.moved = true; }
    if (this.hot?.dragging) this.hot.moved = true;
    const req = this.app.prompt;
    const wantsPoint = (req.active && req.kinds.some((k) => ["point", "distance", "angle"].includes(k))) || !!this.hot;
    if (this.app.isIdle && !this.hot) { this.hoverGrip = this.gripAt(v); this.hover = this.hoverGrip ? null : pick(this.entries, this.world, 6 / this.v.scale); }
    else if (req.active && req.kinds.some((k) => k === "selection" || k === "entity")) this.hover = pick(this.entries, this.world, 6 / this.v.scale);
    else this.hover = null;
    if (wantsPoint) this.sendCursor(); else { this.snap = null; this.engineCursor = null; this.app.live.snapHint = ""; }
    const cp = this.cursorPoint();
    this.app.live.x = cp[0]; this.app.live.y = cp[1];
    this.app.emit("live");
  }
  /** input.cursor: previews and snaps come from the engine; one request in flight at a time. */
  private async sendCursor() {
    if (this.cursorBusy) { this.cursorPending = true; return; }
    this.cursorBusy = true;
    const [x, y] = this.world;
    const st = await this.app.tryCall("input.cursor", { x, y, pixelsPerUnit: this.v.scale });
    this.cursorBusy = false;
    if (st && typeof st === "object") {
      this.snap = st.snap ?? null;
      this.engineCursor = Array.isArray(st.cursor) ? [st.cursor[0], st.cursor[1]] : null;
      this.app.live.snapHint = this.snap ? this.snap.kind.charAt(0).toUpperCase() + this.snap.kind.slice(1) : "";
      this.preview = (st.preview ?? []).map(decodeItem).filter(Boolean) as Item[];
      const p = this.app.prompt;
      if (st.active !== p.active || st.message !== p.message || JSON.stringify(st.keywords) !== JSON.stringify(p.keywords)) this.app.setPrompt(st);
      else { p.base = st.base ?? p.base; }
      this.overlayDirty = true; this.schedule();
    }
    if (this.cursorPending) { this.cursorPending = false; this.sendCursor(); }
  }
  private down(v: [number, number], e: MouseEvent) {
    this.focus();
    if (e.button === 1 || (e.button === 0 && this.spaceDown)) {
      e.preventDefault();
      if (e.button === 1 && performance.now() - this.lastMiddle < 350) { this.zoomExtents(); this.lastMiddle = 0; return; }
      if (e.button === 1) this.lastMiddle = performance.now();
      this.panLast = v; this.overlay.style.cursor = "grabbing"; return;
    }
    if (e.button !== 0) return;
    const app = this.app, req = app.prompt, w = this.world;
    if (this.zoomWindowPending) { this.win = { start: v, current: v, moved: false, purpose: "zoom", shift: false }; return; }
    if (this.hot && !this.hot.dragging) { this.finishGrip(); return; }
    if (req.active) {
      // The engine applies running snaps, grid snap and ortho/polar from the base point (input.point snap:true).
      if (req.kinds.includes("point")) { app.tryCall("input.point", { x: w[0], y: w[1], snap: true, pixelsPerUnit: this.v.scale }).then((st) => st && app.setPrompt(st)); return; }
      if (req.kinds.some((k) => k === "selection" || k === "entity")) {
        const hit = pick(this.entries, w, 6 / this.v.scale);
        if (hit) { app.tryCall("pick", { x: w[0], y: w[1], tolerance: 6 / this.v.scale, add: true, toggle: e.shiftKey }).then((r) => { if (r?.prompt) app.setPrompt(r.prompt); app.refresh(["selection"]); }); }
        else if (req.kinds.includes("selection")) this.win = { start: v, current: v, moved: false, purpose: "request", shift: e.shiftKey };
        return;
      }
      return;
    }
    const g = this.gripAt(v);
    if (g) { this.hot = { grip: g, dragging: true, moved: false }; this.hoverGrip = null; return; }
    const hit = pick(this.entries, w, 6 / this.v.scale);
    if (hit) {
      app.tryCall("pick", { x: w[0], y: w[1], tolerance: 6 / this.v.scale, add: true, toggle: e.shiftKey }).then(() => app.refresh(["selection", "properties"]));
      return;
    }
    this.win = { start: v, current: v, moved: false, purpose: "select", shift: e.shiftKey };
  }
  private up(v: [number, number], e: MouseEvent) {
    if (this.panLast && (e.button === 1 || e.button === 0)) { this.panLast = null; this.overlay.style.cursor = ""; return; }
    if (this.hot?.dragging && e.button === 0) {
      if (this.hot.moved) this.finishGrip(); else this.hot.dragging = false; // click-click grip editing
      return;
    }
    const w = this.win;
    if (!w || e.button !== 0) return;
    this.win = null;
    const app = this.app;
    if (w.purpose === "zoom") {
      this.zoomWindowPending = false;
      if (w.moved) { const a = this.toWorld(w.start[0], w.start[1]), b = this.toWorld(w.current[0], w.current[1]); this.zoomTo([Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[0], b[0]), Math.max(a[1], b[1])]); }
      return;
    }
    if (!w.moved) { if (w.purpose === "select" && !w.shift && app.selection.ids.length) app.tryCall("select.set", { ids: [] }).then(() => app.refresh(["selection", "properties"])); this.overlayDirty = true; this.schedule(); return; }
    const a = this.toWorld(w.start[0], w.start[1]), b = this.toWorld(w.current[0], w.current[1]);
    const crossing = w.current[0] < w.start[0];
    app.tryCall("select.window", { x0: a[0], y0: a[1], x1: b[0], y1: b[1], crossing, add: true, remove: w.shift }).then((r) => { if (r?.prompt) app.setPrompt(r.prompt); app.refresh(["selection", "properties"]); });
    this.overlayDirty = true; this.schedule();
  }
  private async finishGrip() {
    const h = this.hot; if (!h) return;
    this.hot = null;
    const p = this.cursorPoint();
    await this.app.tryCall("grips.drag", { id: h.grip.id, index: h.grip.index, x: p[0], y: p[1], snap: true });
    await this.app.refresh(["drawing", "selection", "properties", "history"]);
  }
  cancelGrip() { if (this.hot) { this.hot = null; this.overlayDirty = true; this.schedule(); return true; } if (this.zoomWindowPending) { this.zoomWindowPending = false; return true; } return false; }
  get view() { return this.v; }
}
