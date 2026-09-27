// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The Mac 3D view's tools beyond navigation: the bottom tool bar with 3D measuring and the move / rotate / scale gizmo
// (ArchiApp/Viewport3DTools.swift), levels in 3D and field of view (Studio3D.swift Level3DMenu), the saved-cameras menu,
// the section box, clipping plane and sun study panels (Viewport3DExtras.swift, Viewport3DTools.swift ClipPlanePanel),
// the steering wheel (Navigation3DPlus.swift), object / door animation playback (SceneEffects.swift AnimationPlayer)
// and the overlay canvas that draws the gizmo and measure markers on top of the model (readsFromDepthBuffer = false).

import type { View3D } from "./view3d";
import { V3, M4, add, sub, scale, len, norm, cross, mul, ident, clamp } from "./math";
import { CameraState, cloneCamera, orbit, basis } from "./camera";
import { UNIT } from "./renderer";
import {
  GizmoMath, GizmoMode, GIZMO_MODES, describeMeasure, levelOffsets, levelVisible, FieldOfView, Anim, ObjectAnimation, splitDoor,
  doorPartOfSegment, LevelInfo, fmt, sunStudy, sunStudyText,
} from "./effects";

const ACCENT_CSS = "#F5C518";
// macOS dark-appearance system colours of the gizmo (NSColor.systemRed / Green / Blue / Purple).
const AXIS_COLORS: Record<number, string> = { 0: "#FF453A", 1: "#32D74B", 3: "#0A84FF", 2: "#BF5AF2", 4: "#FFFFFF" };

export interface TransformRequest { op: "move" | "movez" | "rotate" | "scale"; axis: number; amount: number; pivot: [number, number]; ids: string[] }

export interface ExtrasHost {
  /** Commits a gizmo drag (the engine's view3d.transform: one undo step). */
  onTransform?: (t: TransformRequest) => void;
  /** Stores a drawing variable (SECTIONPLANE, SUNSTUDY …) as one undo step. */
  onVariable?: (name: string, value: string | null) => void;
  /** "Save Current Camera…" and camera deletion (namedViews). */
  onSaveCamera?: (camera: CameraState) => void;
  onDeleteCamera?: (name: string) => void;
  /** Prints to the command line history (measure results, gizmo, two-point messages). */
  print?: (text: string) => void;
  /** Live hint (Mac model.live.snapHint), e.g. "Move X 1200". */
  hint?: (text: string) => void;
  /** Grid snap step of gizmo moves (drawing units; 0 = off). */
  gridStep?: () => number;
  /** Runs a command line in the engine (Ctrl-click sub-object editing: SUBOBJECT #id Face *x,y,z). */
  runCommand?: (line: string) => void;
  /** SUBOBJECTMODE of the drawing (Face, Edge or Vertex). */
  subObjectMode?: () => string;
}

const BOX_FACES: { n: V3 }[] = [{ n: [-1, 0, 0] }, { n: [1, 0, 0] }, { n: [0, -1, 0] }, { n: [0, 1, 0] }, { n: [0, 0, -1] }, { n: [0, 0, 1] }];

interface GizmoDrag { axis: number; start: [number, number]; amount: number; pivot: V3 }
interface BoxDrag { face: number; start: [number, number]; base: { on: boolean; min: V3; max: V3 }; amount: number }

export class View3DExtras {
  readonly overlay: HTMLCanvasElement;
  readonly toolbar: HTMLDivElement;
  private rulerBtn!: HTMLButtonElement;
  private segs: HTMLButtonElement[] = [];
  private text!: HTMLSpanElement;
  gizmoMode: GizmoMode = "Off";
  measureActive = false;
  measurePoints: V3[] = [];
  measureText = "";
  private drag: GizmoDrag | null = null;
  private boxDrag: BoxDrag | null = null;
  /** Levels in 3D (LevelView3DState). */
  levels: LevelInfo[] = [];
  currentLevel: number | null = null;
  isolate: number | null = null;
  explodeGap = 0;       // model mm
  /** Object animations (OBJANIM) and playback. */
  animations: ObjectAnimation[] = [];
  private playT0 = 0;
  playing = false;
  animTime = -1;
  private splitDone = new Set<string>();
  /** Steering wheel. */
  wheelVisible = false;
  private wheelEl: HTMLDivElement | null = null;
  private history: CameraState[] = [];
  wheelPivot: V3 | null = null;
  /** Sun study state (SUNSTUDY). */
  site = { latitude: 44.43, longitude: 26.1, day: 172, hour: 15 };

  constructor(readonly view: View3D, readonly host: ExtrasHost = {}) {
    this.overlay = document.createElement("canvas");
    this.overlay.className = "v3d-overlay";
    view.el.insertBefore(this.overlay, view.canvas.nextSibling);
    this.toolbar = this.buildToolbar();
    view.el.append(this.toolbar);
    injectExtrasStyles();
  }

  // MARK: bottom tool bar (Viewport3DToolBar)

  private buildToolbar(): HTMLDivElement {
    const bar = document.createElement("div");
    bar.className = "v3d-toolbar";
    const r = document.createElement("button");
    r.className = "v3d-tbtn";
    r.title = "Measure in 3D: click two points on the model (MEASURE3D)";
    r.append(this.view.iconFor("ruler", "📏"));
    r.addEventListener("click", (e) => { e.stopPropagation(); this.setMeasure(!this.measureActive); });
    this.rulerBtn = r;
    const seg = document.createElement("div");
    seg.className = "v3d-seg";
    seg.title = "Move (X/Y/Z arrows) or rotate gizmo for the selection (GIZMO3D); Shift snaps rotation to 15°";
    for (const m of GIZMO_MODES) {
      const b = document.createElement("button");
      b.textContent = m;
      b.addEventListener("click", (e) => { e.stopPropagation(); this.setGizmo(m); });
      this.segs.push(b);
      seg.append(b);
    }
    this.text = document.createElement("span");
    this.text.className = "v3d-ttext";
    bar.append(r, seg, this.text);
    this.refreshToolbar();
    return bar;
  }

  refreshToolbar() {
    this.rulerBtn.classList.toggle("on", this.measureActive);
    this.segs.forEach((b, i) => b.classList.toggle("on", GIZMO_MODES[i] === this.gizmoMode));
    const t = this.drag ? GizmoMath.hint(this.drag.axis, this.drag.amount) : this.measureText;
    this.text.textContent = t;
    this.text.hidden = !(this.measureActive || t);
  }

  setGizmo(m: GizmoMode) {
    this.gizmoMode = m;
    if (m !== "Off" && this.measureActive) this.setMeasure(false);
    this.refreshToolbar();
    this.view.invalidate();
  }

  setMeasure(on: boolean) {
    this.measureActive = on;
    this.measurePoints = [];
    this.measureText = on ? "Measure: click the first point on the model" : "";
    if (on) this.gizmoMode = "Off";
    this.refreshToolbar();
    this.view.invalidate();
  }

  private addMeasurePoint(p: V3) {
    if (this.measurePoints.length >= 2) this.measurePoints = [];
    this.measurePoints.push(p);
    this.measureText = this.measurePoints.length === 1
      ? `Measure: click the second point (from ${fmt(p[0], 0)}, ${fmt(p[1], 0)}, ${fmt(p[2], 0)})`
      : describeMeasure(this.measurePoints[0], this.measurePoints[1]);
    if (this.measurePoints.length === 2) this.host.print?.(this.measureText);
    this.refreshToolbar();
    this.view.invalidate();
  }

  // MARK: gizmo geometry (refreshGizmo)

  private selectionIds(): string[] { return this.view.getSelection(); }

  /** Plan centre and top of the selection (model mm), as selectionCenter. */
  selectionCenter(ids = this.selectionIds()): V3 | null {
    const set = new Set(ids);
    const lo: V3 = [Infinity, Infinity, Infinity], hi: V3 = [-Infinity, -Infinity, -Infinity];
    for (const m of this.view.scene.meshes) {
      if (m.id == null || !set.has(m.id) || m.hidden) continue;
      for (let k = 0; k < 3; k++) { lo[k] = Math.min(lo[k], m.min[k]); hi[k] = Math.max(hi[k], m.max[k]); }
    }
    if (!isFinite(lo[0])) return null;
    return [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, hi[2]];
  }

  private gizmoSize(): number {
    const s = this.view.scene;
    const ext = s.empty ? 10000 : Math.max(s.max[0] - s.min[0], s.max[1] - s.min[1]);
    return Math.max(400, ext / 12);
  }

  /** Gizmo position (model mm): above the selection, following a move drag. */
  private gizmoOrigin(): V3 | null {
    if (this.drag) {
      const d = this.drag, p = d.pivot;
      if (d.axis === 0) return [p[0] + d.amount, p[1], p[2]];
      if (d.axis === 1) return [p[0], p[1] + d.amount, p[2]];
      if (d.axis === 3) return [p[0], p[1], p[2] + d.amount];
      return p;
    }
    const c = this.selectionCenter();
    return c ? [c[0], c[1], c[2] + 50] : null;
  }

  private axisDir(axis: number): V3 { return axis === 0 ? [1, 0, 0] : axis === 1 ? [0, 1, 0] : [0, 0, 1]; }

  /** Gizmo handle under a view point (0 = X, 1 = Y, 2 = rotation ring, 3 = Z, 4 = scale). */
  gizmoAxis(x: number, y: number): number | null {
    if (this.gizmoMode === "Off") return null;
    const o = this.gizmoOrigin();
    if (!o) return null;
    const size = this.gizmoSize();
    const P = (q: V3) => this.view.project(q);
    const c = P(o);
    if (!c) return null;
    const px = this.pxPerMM(o);
    const near = (a: [number, number], b: [number, number], w: number) => distSeg([x, y], a, b) <= Math.max(6, w);
    if (this.gizmoMode === "Move") {
      let best: number | null = null, bd = Infinity;
      for (const axis of [0, 1, 3]) {
        const e = P(add(o, scale(this.axisDir(axis), size * 1.25)));
        if (!e) continue;
        const d = distSeg([x, y], c, e);
        if (d <= Math.max(6, size * 0.09 * px) && d < bd) { bd = d; best = axis; }
      }
      return best;
    }
    if (this.gizmoMode === "Scale") {
      const h = P(add(o, [size * 0.75, size * 0.75, 0]));
      if (h && Math.abs(x - h[0]) <= Math.max(7, size * 0.09 * px) && Math.abs(y - h[1]) <= Math.max(7, size * 0.09 * px)) return 4;
      if (Math.hypot(x - c[0], y - c[1]) <= Math.max(6, size * 0.05 * px)) return 4;
      return null;
    }
    const pts = ringPoints(o, size * 0.7).map(P);
    for (let i = 0; i + 1 < pts.length; i++) { const a = pts[i], b = pts[i + 1]; if (a && b && near(a, b, size * 0.035 * px + 3)) return 2; }
    return null;
  }

  private pxPerMM(o: V3): number {
    const b = basis(this.view.getCamera());
    const a = this.view.project(o), c = this.view.project(add(o, scale(b.r, 1000)));
    if (!a || !c) return 0.01;
    return Math.hypot(c[0] - a[0], c[1] - a[1]) / 1000;
  }

  /** Amount of a drag from a to b (view points, y down): mm along an axis, radians, or a scale factor. */
  private gizmoAmount(axis: number, a: [number, number], b: [number, number], shift: boolean): number {
    const o = this.drag?.pivot ?? this.gizmoOrigin();
    if (!o) return 0;
    const sc = this.view.project(o);
    if (!sc) return 0;
    const H = this.view.el.clientHeight;
    const up = (p: [number, number]): [number, number] => [p[0], H - p[1]];   // AppKit view coordinates (y up)
    if (axis === 4) return GizmoMath.scaleFactor(up(sc), up(a), up(b), shift ? 0.1 : 0);
    if (axis === 2) return GizmoMath.snap(GizmoMath.sweep(up(sc), up(a), up(b)), shift ? Math.PI / 12 : 0);
    const unit = 1000;
    const se = this.view.project(add(o, scale(this.axisDir(axis), unit)));
    if (!se) return 0;
    const s0 = up(sc), s1 = up(se), pa = up(a), pb = up(b);
    let d = GizmoMath.axisDelta([pb[0] - pa[0], pb[1] - pa[1]], [(s1[0] - s0[0]) / unit, (s1[1] - s0[1]) / unit]);
    const step = this.host.gridStep?.() ?? 0;
    if (step > 0) d = GizmoMath.snap(d, step);
    return d;
  }

  /** Live preview: moves / rotates / scales the selected meshes (gizmoPreview). */
  private preview(axis: number, amount: number) {
    const d = this.drag!;
    d.amount = amount;
    const m = GizmoMath.matrix(axis, amount, d.pivot);
    const set = new Set(this.selectionIds());
    for (const mesh of this.view.scene.meshes) if (mesh.id != null && set.has(mesh.id)) mesh.xf = mul(m, this.baseTransform(mesh));
    this.host.hint?.(GizmoMath.hint(axis, amount));
    this.refreshToolbar();
    this.view.invalidate();
  }

  private commit() {
    const d = this.drag!;
    this.drag = null;
    this.applyLevelView();
    this.refreshToolbar();
    this.host.hint?.("");
    const ids = this.selectionIds();
    if (d.axis === 4) { if (!(d.amount > 0) || Math.abs(d.amount - 1) <= 1e-9) return; this.host.onTransform?.({ op: "scale", axis: 4, amount: d.amount, pivot: [d.pivot[0], d.pivot[1]], ids }); return; }
    if (Math.abs(d.amount) <= 1e-9) return;
    const op = d.axis === 2 ? "rotate" : d.axis === 3 ? "movez" : "move";
    this.host.onTransform?.({ op, axis: d.axis, amount: d.amount, pivot: [d.pivot[0], d.pivot[1]], ids });
  }

  // MARK: pointer hooks (called by View3D before its own navigation)

  pointerDown(x: number, y: number, e: PointerEvent): boolean {
    if (e.button !== 0) return false;
    const face = this.boxFaceAt(x, y);
    const box = this.view.getSectionBox();
    if (face != null && box) { this.boxDrag = { face, start: [x, y], base: { on: box.on, min: [...box.min] as V3, max: [...box.max] as V3 }, amount: 0 }; return true; }
    const axis = this.gizmoAxis(x, y);
    if (axis != null) {
      const o = this.gizmoOrigin()!;
      this.drag = { axis, start: [x, y], amount: axis === 4 ? 1 : 0, pivot: o };
      return true;
    }
    return false;
  }
  pointerMove(x: number, y: number, e: PointerEvent): boolean {
    if (this.boxDrag) {
      const d = this.boxDrag, c = boxFaceCenter(d.base, d.face), n = BOX_FACES[d.face].n;
      const s0 = this.view.project(c), s1 = this.view.project(add(c, scale(n, 1000)));
      if (s0 && s1) {
        const H = this.view.el.clientHeight;
        d.amount = GizmoMath.axisDelta([x - d.start[0], (H - y) - (H - d.start[1])], [(s1[0] - s0[0]) / 1000, ((H - s1[1]) - (H - s0[1])) / 1000]);
        this.view.setSectionBox(boxMoved(d.base, d.face, d.amount));
      }
      return true;
    }
    if (!this.drag) return false;
    this.preview(this.drag.axis, this.gizmoAmount(this.drag.axis, this.drag.start, [x, y], e.shiftKey));
    return true;
  }
  pointerUp(x: number, y: number, e: PointerEvent, click: boolean): boolean {
    if (this.boxDrag) {
      this.pointerMove(x, y, e);
      const d = this.boxDrag; this.boxDrag = null;
      if (Math.abs(d.amount) > 1e-9) this.view.commitSectionBox(boxMoved(d.base, d.face, d.amount));
      else this.view.setSectionBox(d.base);
      return true;
    }
    if (this.drag) { this.pointerMove(x, y, e); this.commit(); return true; }
    if (click && this.measureActive) {
      const p = this.view.pointAt(x, y);
      if (p) this.addMeasurePoint(p);
      return true;
    }
    return false;
  }
  get dragging() { return !!this.drag || !!this.boxDrag; }

  /** Ctrl-click on a solid (M3D-052): SUBOBJECT #id Face|Edge|Vertex *x,y,z for the point under the cursor. */
  subObjectPick(x: number, y: number): boolean {
    if (!this.host.runCommand) return false;
    const hit = this.view.hitAt(x, y);
    if (!hit || hit.kind !== "solid" || hit.id == null) return false;
    const m = this.host.subObjectMode?.() ?? "Face";
    const mode = ["Face", "Edge", "Vertex"].includes(m) ? m : "Face";
    this.host.runCommand(`SUBOBJECT #${hit.id} ${mode} *${fmt(hit.point[0], 6)},${fmt(hit.point[1], 6)},${fmt(hit.point[2], 6)}`);
    return true;
  }

  // MARK: section box face grips (SectionBoxGrips.swift)

  /** Face grip under a view point (0 = −X, 1 = +X, 2 = −Y, 3 = +Y, 4 = −Z, 5 = +Z). */
  boxFaceAt(x: number, y: number): number | null {
    const b = this.view.getSectionBox();
    if (!b?.on) return null;
    let best: number | null = null, bd = Infinity;
    for (let f = 0; f < 6; f++) {
      const c = boxFaceCenter(b, f), p = this.view.project(c);
      if (!p) continue;
      const r = Math.max(6, this.gripRadius(b) * this.pxPerMM(c) + 3);
      const d = Math.hypot(x - p[0], y - p[1]);
      if (d <= r && d < bd) { bd = d; best = f; }
    }
    return best;
  }

  private gripRadius(b: { min: V3; max: V3 }): number { return Math.max(60, len(sub(b.max, b.min)) * 0.0125); }

  // MARK: overlay drawing

  draw() {
    const cv = this.overlay, el = this.view.el;
    const dpr = Math.max(1, window.devicePixelRatio || 1);
    const w = el.clientWidth, h = el.clientHeight;
    if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }
    const g = cv.getContext("2d");
    if (!g) return;
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, w, h);
    this.drawBoxGrips(g);
    this.drawMeasure(g);
    this.drawGizmo(g);
  }

  private drawBoxGrips(g: CanvasRenderingContext2D) {
    const b = this.view.getSectionBox();
    if (!b?.on) return;
    g.fillStyle = ACCENT_CSS;
    for (let f = 0; f < 6; f++) {
      const c = boxFaceCenter(b, f), p = this.view.project(c);
      if (!p) continue;
      g.beginPath(); g.arc(p[0], p[1], Math.max(3, this.gripRadius(b) * this.pxPerMM(c)), 0, Math.PI * 2); g.fill();
    }
  }

  private drawMeasure(g: CanvasRenderingContext2D) {
    const pts = this.measurePoints;
    if (!this.measureActive || !pts.length) return;
    const s = this.view.scene;
    const r = Math.max(20, (s.empty ? 10000 : Math.max(s.max[0] - s.min[0], s.max[1] - s.min[1])) / 300);
    g.fillStyle = ACCENT_CSS; g.strokeStyle = ACCENT_CSS; g.lineWidth = 1.5;
    const P = pts.map((p) => this.view.project(p));
    if (P.length === 2 && P[0] && P[1]) { g.beginPath(); g.moveTo(P[0][0], P[0][1]); g.lineTo(P[1][0], P[1][1]); g.stroke(); }
    pts.forEach((p, i) => {
      const q = P[i]; if (!q) return;
      const rad = Math.max(3, r * this.pxPerMM(p));
      g.beginPath(); g.arc(q[0], q[1], rad, 0, Math.PI * 2); g.fill();
    });
  }

  private drawGizmo(g: CanvasRenderingContext2D) {
    if (this.gizmoMode === "Off" || !this.selectionIds().length) return;
    const o = this.gizmoOrigin();
    if (!o) return;
    const size = this.gizmoSize();
    const px = this.pxPerMM(o);
    const P = (q: V3) => this.view.project(q);
    const c = P(o);
    if (!c) return;
    g.lineCap = "butt";
    if (this.gizmoMode === "Move") {
      for (const axis of [0, 1, 3]) {
        const d = this.axisDir(axis);
        const s1 = P(add(o, scale(d, size))), tip = P(add(o, scale(d, size * 1.25)));
        if (!s1 || !tip) continue;
        const col = AXIS_COLORS[axis];
        g.strokeStyle = col; g.fillStyle = col;
        g.lineWidth = Math.max(2.5, size * 0.06 * px);
        g.beginPath(); g.moveTo(c[0], c[1]); g.lineTo(s1[0], s1[1]); g.stroke();
        const ang = Math.atan2(tip[1] - s1[1], tip[0] - s1[0]);
        const hw = Math.max(5, size * 0.09 * px);
        g.beginPath();
        g.moveTo(tip[0], tip[1]);
        g.lineTo(s1[0] + Math.cos(ang + Math.PI / 2) * hw, s1[1] + Math.sin(ang + Math.PI / 2) * hw);
        g.lineTo(s1[0] + Math.cos(ang - Math.PI / 2) * hw, s1[1] + Math.sin(ang - Math.PI / 2) * hw);
        g.closePath(); g.fill();
      }
    } else if (this.gizmoMode === "Scale") {
      const hpt = P(add(o, [size * 0.75, size * 0.75, 0]));
      if (!hpt) return;
      g.strokeStyle = "#FFFFFF"; g.lineWidth = 1;
      g.beginPath(); g.moveTo(c[0], c[1]); g.lineTo(hpt[0], hpt[1]); g.stroke();
      const hs = Math.max(6, size * 0.09 * px), cs = Math.max(4, size * 0.05 * px);
      g.fillStyle = "#FFFFFF"; g.fillRect(hpt[0] - hs, hpt[1] - hs, hs * 2, hs * 2);
      g.fillStyle = ACCENT_CSS; g.fillRect(c[0] - cs, c[1] - cs, cs * 2, cs * 2);
    } else {
      const angle = this.drag?.axis === 2 ? this.drag.amount : 0;
      const pts = ringPoints(o, size * 0.7, angle).map(P);
      g.strokeStyle = AXIS_COLORS[2]; g.lineWidth = Math.max(2.5, size * 0.07 * px);
      g.beginPath();
      pts.forEach((q, i) => { if (!q) return; if (i === 0) g.moveTo(q[0], q[1]); else g.lineTo(q[0], q[1]); });
      g.closePath(); g.stroke();
    }
  }

  // MARK: levels in 3D (applyLevelView) and animations

  /** Transform a mesh has without a gizmo drag: explode offset of its level. */
  baseTransform(mesh: { level: number | null }): M4 {
    if (this.explodeGap <= 1e-9 || mesh.level == null) return ident();
    const off = levelOffsets(this.levels, this.explodeGap).get(mesh.level) ?? 0;
    const m = ident(); m[14] = off;
    return m;
  }

  setLevelView(isolate: number | null, gap: number) {
    this.isolate = isolate; this.explodeGap = Math.max(0, gap);
    this.applyLevelView();
    this.view.refreshOverlayPublic();
  }

  /** Hides elements of other levels and lifts each level by its explode offset; applies the animation state. */
  applyLevelView() {
    const offs = levelOffsets(this.levels, this.explodeGap);
    for (const m of this.view.scene.meshes) {
      m.hidden = !levelVisible(m.level, this.isolate);
      const off = m.level != null ? offs.get(m.level) ?? 0 : 0;
      if (Math.abs(off) > 1e-9) { const x = ident(); x[14] = off; m.xf = x; } else m.xf = null;
    }
    if (this.animTime >= 0) this.applyAnimations(this.animTime);
    this.view.invalidate();
  }

  get levelViewActive() { return this.isolate != null || this.explodeGap > 1e-9; }

  setAnimations(a: ObjectAnimation[]) {
    this.animations = a;
    this.splitDone.clear();
    this.prepareDoors();
  }

  /** Splits animated doors into frame and leaves (once per model load). */
  prepareDoors() {
    const byTarget = new Map<string, ObjectAnimation[]>();
    for (const a of this.animations) if (a.kind === "Door" && a.leaf) { const k = String(a.target); byTarget.set(k, [...(byTarget.get(k) ?? []), a]); }
    for (const [id, anims] of byTarget) {
      if (this.splitDone.has(id)) continue;
      const leaves = anims.sort((x, y) => (x.leafIndex ?? 0) - (y.leafIndex ?? 0)).map((a) => a.leaf!);
      for (const m of this.view.scene.meshes) {
        if (m.id !== id || m.parts) continue;
        const r = splitDoor(m.positions, m.indices, leaves);
        this.view.scene.splitMesh(m, r.indices, r.ranges, (a, b) => doorPartOfSegment(a, b, leaves));
      }
      this.splitDone.add(id);
    }
  }

  /** Applies the animations at time t (ObjectAnimations.apply): door leaves turn about their hinge, objects move. */
  applyAnimations(t: number) {
    const leafIndex = new Map<string, number>();
    for (const a of this.animations) {
      const id = String(a.target);
      const m = ObjectAnimationMatrix(a, t);
      if (a.kind === "Door") {
        const k = leafIndex.get(id) ?? 0; leafIndex.set(id, k + 1);
        for (const mesh of this.view.scene.meshes) if (mesh.id === id && mesh.parts && mesh.parts[k + 1]) mesh.parts[k + 1].xf = mul(this.baseTransform(mesh), m);
      } else {
        for (const mesh of this.view.scene.meshes) if (mesh.id === id) mesh.xf = mul(this.baseTransform(mesh), m);
      }
    }
    this.view.invalidate();
  }

  play(on: boolean) {
    this.playing = on && this.animations.length > 0;
    if (this.playing) { this.prepareDoors(); this.playT0 = performance.now(); this.animTime = 0; }
    else { this.animTime = -1; this.applyLevelView(); for (const m of this.view.scene.meshes) if (m.parts) m.parts.forEach((p) => (p.xf = null)); }
    this.view.invalidate();
  }

  /** Frame loop hook: advances the animation; true while something moves. */
  tick(now: number): boolean {
    if (!this.playing) return false;
    const total = Anim.duration(this.animations);
    let t = (now - this.playT0) / 1000;
    if (total > 0 && t > total + 0.5) { this.playT0 = now; t = 0; }
    this.animTime = t;
    this.applyAnimations(t);
    return true;
  }

  // MARK: Save Camera sheet (SaveCameraSheet)

  askCameraName(def: string): Promise<string | null> {
    return new Promise((resolve) => {
      const back = document.createElement("div"); back.className = "v3d-sheetback";
      const s = document.createElement("div"); s.className = "v3d-sheet";
      const t = document.createElement("div"); t.className = "v3d-sheet-title"; t.textContent = "Save Camera";
      const inp = document.createElement("input"); inp.type = "text"; inp.value = def; inp.placeholder = "Camera name"; inp.spellcheck = false;
      const note = document.createElement("div"); note.className = "v3d-small";
      note.textContent = "Saved with the drawing; restore it from the camera menu in the 3D view or with the CAMERA command.";
      const row = document.createElement("div"); row.className = "v3d-sheet-row";
      const cancel = document.createElement("button"); cancel.className = "v3d-flat"; cancel.textContent = "Cancel";
      const save = document.createElement("button"); save.className = "v3d-flat v3d-prominent"; save.textContent = "Save";
      row.append(cancel, save); s.append(t, inp, note, row); back.append(s);
      const done = (v: string | null) => { back.remove(); resolve(v); };
      const upd = () => { save.disabled = !inp.value.trim(); };
      inp.addEventListener("input", upd);
      inp.addEventListener("keydown", (e) => { e.stopPropagation(); if (e.key === "Enter" && inp.value.trim()) done(inp.value.trim()); if (e.key === "Escape") done(null); });
      cancel.addEventListener("click", () => done(null));
      save.addEventListener("click", () => { if (inp.value.trim()) done(inp.value.trim()); });
      back.addEventListener("pointerdown", (e) => e.stopPropagation());
      this.view.el.append(back);
      upd(); inp.focus(); inp.select();
    });
  }

  // MARK: steering wheel (SteeringWheelView)

  toggleWheel(on = !this.wheelVisible) {
    this.wheelVisible = on;
    this.wheelEl?.remove(); this.wheelEl = null;
    if (on) { this.wheelEl = this.buildWheel(); this.view.panelHostEl.append(this.wheelEl); }
  }

  pushHistory() { this.history.push(this.view.getCamera()); if (this.history.length > 50) this.history.shift(); }

  private buildWheel(): HTMLDivElement {
    const S = 170, inner = S * 0.18, middle = S * 0.33, outer = S * 0.5;
    const outerW = ["ZOOM", "PAN", "ORBIT", "REWIND"], innerW = ["CENTER", "WALK", "UP/DOWN", "LOOK"];
    const el = document.createElement("div");
    el.className = "v3d-wheel";
    el.title = "Steering wheel: press a wedge and drag (Zoom, Orbit, Pan, Look, Walk, Up/Down); click Center or Rewind";
    const labels: Record<string, HTMLSpanElement> = {};
    [...outerW, ...innerW].forEach((w) => {
      const isOuter = outerW.includes(w);
      const i = (isOuter ? outerW : innerW).indexOf(w);
      const r = isOuter ? (middle + outer) / 2 : (inner + middle) / 2;
      const a = (i * Math.PI) / 2;
      const s = document.createElement("span");
      s.textContent = w;
      s.style.left = S / 2 + Math.sin(a) * r + "px"; s.style.top = S / 2 - Math.cos(a) * r + "px";
      labels[w] = s; el.append(s);
    });
    const ring = document.createElement("div"); ring.className = "v3d-wheel-ring"; el.append(ring);
    const hole = document.createElement("div"); hole.className = "v3d-wheel-hole"; el.append(hole);
    const close = document.createElement("button"); close.className = "v3d-wheel-x"; close.textContent = "✕"; close.title = "Close the steering wheel";
    close.addEventListener("click", (e) => { e.stopPropagation(); this.toggleWheel(false); });
    el.append(close);
    const wedge = (x: number, y: number): string | null => {
      const dx = x - S / 2, dy = S / 2 - y, r = Math.hypot(dx, dy);
      if (r < inner || r > outer) return null;
      let a = (Math.atan2(dx, dy) * 180) / Math.PI; if (a < 0) a += 360;
      const i = Math.floor((a + 45) / 90) % 4;
      return r >= middle ? outerW[i] : innerW[i];
    };
    let active: string | null = null, last: [number, number] = [0, 0], moved = false;
    el.addEventListener("pointerdown", (e) => {
      if ((e.target as HTMLElement).closest(".v3d-wheel-x")) return;
      e.stopPropagation();
      const r = el.getBoundingClientRect();
      active = wedge(e.clientX - r.left, e.clientY - r.top);
      last = [e.clientX, e.clientY]; moved = false;
      if (active) { this.pushHistory(); el.setPointerCapture(e.pointerId); labels[active]?.classList.add("on"); }
    });
    el.addEventListener("pointermove", (e) => {
      if (!active) return;
      const dx = e.clientX - last[0], dy = last[1] - e.clientY;
      last = [e.clientX, e.clientY];
      if (Math.abs(dx) + Math.abs(dy) > 0) { moved = true; this.wheelOp(active, dx, dy); }
    });
    el.addEventListener("pointerup", () => {
      if (active && !moved) {
        if (active === "CENTER") this.wheelCenter();
        if (active === "REWIND") { this.history.pop(); this.wheelRewind(); }
      }
      if (active) labels[active]?.classList.remove("on");
      active = null;
    });
    return el;
  }

  private pivot(): V3 { return this.wheelPivot ?? this.view.getCamera().target; }

  wheelOp(w: string, dx: number, dy: number) {
    let c = this.view.getCamera();
    const piv = this.pivot();
    switch (w) {
      case "ZOOM": {
        const k = Math.exp(-dy * 0.01);
        if (c.ortho) { c.orthoScale = Math.max(0.05, c.orthoScale * k); break; }
        const off = sub(c.eye, piv);
        if (len(off) * k <= 0.05) return;
        c.eye = add(piv, scale(off, k));
        break;
      }
      case "ORBIT": c = orbit({ ...c, target: piv }, dx, dy); c.target = piv; break;
      case "PAN": {
        const d = Math.max(len(sub(c.eye, piv)), 1) * 0.0025;
        const b = basis(c);
        const t = add(scale(b.r, -dx * d), scale(b.u, dy * d));
        c.eye = add(c.eye, t); c.target = add(c.target, t); this.wheelPivot = add(piv, t);
        break;
      }
      case "LOOK": {
        const f = norm(sub(c.target, c.eye));
        let yaw = Math.atan2(f[1], f[0]), pitch = Math.asin(clamp(f[2], -1, 1));
        yaw -= dx * 0.005; pitch = clamp(pitch + dy * 0.005, -1.4, 1.4);
        const nf: V3 = [Math.cos(pitch) * Math.cos(yaw), Math.cos(pitch) * Math.sin(yaw), Math.sin(pitch)];
        c.target = add(c.eye, scale(nf, Math.max(len(sub(c.target, c.eye)), 1)));
        break;
      }
      case "UP/DOWN": c.eye = add(c.eye, [0, 0, dy * 0.02]); c.target = add(c.target, [0, 0, dy * 0.02]); break;
      case "WALK": {
        const f = sub(c.target, c.eye), h = Math.hypot(f[0], f[1]);
        if (h < 1e-6) return;
        const t: V3 = [(f[0] / h) * dy * 0.03, (f[1] / h) * dy * 0.03, 0];
        c.eye = add(c.eye, t); c.target = add(c.target, t);
        break;
      }
      default: return;
    }
    c.up = [0, 0, 1];
    this.view.setCamera(c, false);
  }

  wheelCenter() {
    const sc = this.selectionCenter();
    const p: V3 = sc ? scale(sc, UNIT) : this.view.sceneCenterWorld();
    this.wheelPivot = p;
    const c = this.view.getCamera();
    this.view.setCamera({ ...c, target: p, up: [0, 0, 1] }, false);
  }

  wheelRewind(): boolean {
    const c = this.history.pop();
    if (!c) return false;
    this.view.setCamera(c, false);
    return true;
  }
}

function boxFaceCenter(b: { min: V3; max: V3 }, f: number): V3 {
  const c: V3 = [(b.min[0] + b.max[0]) / 2, (b.min[1] + b.max[1]) / 2, (b.min[2] + b.max[2]) / 2];
  const k = Math.floor(f / 2);
  c[k] = f % 2 === 0 ? b.min[k] : b.max[k];
  return c;
}

/** SectionBox.moved: one face moved outwards by d (negative inwards), never thinner than 10 mm. */
export function boxMoved(b: { on: boolean; min: V3; max: V3 }, f: number, d: number): { on: boolean; min: V3; max: V3 } {
  const min = [...b.min] as V3, max = [...b.max] as V3, k = Math.floor(f / 2);
  if (f % 2 === 0) min[k] = Math.min(b.min[k] - d, b.max[k] - 10); else max[k] = Math.max(b.max[k] + d, b.min[k] + 10);
  return { on: b.on, min, max };
}

function ObjectAnimationMatrix(a: ObjectAnimation, t: number): M4 { return Anim.matrix(a, t); }

function ringPoints(o: V3, r: number, angle = 0): V3[] {
  const out: V3[] = [];
  for (let i = 0; i <= 64; i++) { const a = angle + (i / 64) * Math.PI * 2; out.push([o[0] + Math.cos(a) * r, o[1] + Math.sin(a) * r, o[2]]); }
  return out;
}

function distSeg(p: [number, number], a: [number, number], b: [number, number]): number {
  const dx = b[0] - a[0], dy = b[1] - a[1];
  const l2 = dx * dx + dy * dy;
  const t = l2 > 0 ? clamp(((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2, 0, 1) : 0;
  return Math.hypot(p[0] - (a[0] + dx * t), p[1] - (a[1] + dy * t));
}

// Unused imports kept typed for tree-shaking clarity.
void cross; void cloneCamera; void FieldOfView; void sunStudy; void sunStudyText;

let styled = false;
function injectExtrasStyles() {
  if (styled || typeof document === "undefined") return;
  styled = true;
  const css = document.createElement("style");
  css.textContent = `
.v3d-overlay{position:absolute;inset:0;width:100%;height:100%;pointer-events:none}
.v3d-toolbar{position:absolute;left:10px;bottom:10px;display:flex;align-items:center;gap:8px;padding:5px 10px;border-radius:999px;background:#26272B;border:1px solid rgba(255,255,255,.08);color:#E6E6E6;font:11px -apple-system,"Segoe UI",system-ui,sans-serif;max-width:calc(100% - 140px)}
.v3d-tbtn{border:0;background:transparent;color:#E6E6E6;padding:0;display:grid;place-items:center;width:20px;height:20px}
.v3d-tbtn.on{color:#F5C518}
.v3d-seg{display:flex;width:220px;border-radius:6px;background:#1E1F22;padding:1px;border:1px solid rgba(255,255,255,.08)}
.v3d-seg button{flex:1;border:0;background:transparent;color:#E6E6E6;font:11px -apple-system,"Segoe UI",system-ui,sans-serif;padding:2px 0;border-radius:5px}
.v3d-seg button.on{background:#4A4B50;color:#FFFFFF}
.v3d-ttext{font:11px ui-monospace,"SF Mono",Menlo,Consolas,monospace;color:#E6E6E6;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.v3d-wheel{position:relative;width:170px;height:170px;border-radius:50%;background:rgba(38,39,43,.92);color:#E6E6E6;font:600 9px -apple-system,"Segoe UI",system-ui,sans-serif;touch-action:none}
.v3d-wheel span{position:absolute;transform:translate(-50%,-50%);pointer-events:none}
.v3d-wheel span.on{color:#F5C518}
.v3d-wheel-ring{position:absolute;left:28.9px;top:28.9px;width:112.2px;height:112.2px;border-radius:50%;border:1px solid rgba(255,255,255,.15);box-sizing:border-box;pointer-events:none}
.v3d-wheel-hole{position:absolute;left:54.4px;top:54.4px;width:61.2px;height:61.2px;border-radius:50%;background:#2F3035;pointer-events:none}
.v3d-wheel-x{position:absolute;right:2px;top:2px;border:0;background:transparent;color:#9A9BA1;font-size:11px}
.v3d-menu .v3d-mdiv{height:1px;background:rgba(255,255,255,.1);margin:4px 6px}
.v3d-menu .v3d-mhead{padding:4px 10px;color:#9A9BA1;font:11px -apple-system,"Segoe UI",system-ui,sans-serif}
.v3d-menu button.sub{padding-left:22px}
.v3d-panel .v3d-small{color:#9A9BA1;font-size:10px}
.v3d-panel .v3d-mono{font:11px ui-monospace,"SF Mono",Menlo,Consolas,monospace}
.v3d-segp{display:flex;border-radius:6px;background:#1E1F22;padding:1px;border:1px solid rgba(255,255,255,.08)}
.v3d-segp button{flex:1;border:0;background:transparent;color:#E6E6E6;font:11px -apple-system,"Segoe UI",system-ui,sans-serif;padding:2px 0;border-radius:5px}
.v3d-segp button.on{background:#4A4B50}
.v3d-sheetback{position:absolute;inset:0;display:flex;align-items:flex-start;justify-content:center;background:rgba(0,0,0,.25);z-index:30}
.v3d-sheet{margin-top:40px;width:312px;box-sizing:border-box;padding:16px;background:#26272B;border:1px solid rgba(255,255,255,.1);border-radius:10px;box-shadow:0 12px 32px rgba(0,0,0,.5);display:flex;flex-direction:column;gap:12px;color:#E6E6E6;font:12px -apple-system,"Segoe UI",system-ui,sans-serif}
.v3d-sheet-title{font-size:13px;font-weight:600}
.v3d-sheet input{width:280px;box-sizing:border-box;background:#1E1F22;border:1px solid rgba(255,255,255,.12);border-radius:5px;color:#E6E6E6;padding:4px 6px;font:12px -apple-system,"Segoe UI",system-ui,sans-serif;outline:none}
.v3d-sheet input:focus{border-color:#F5C518}
.v3d-sheet-row{display:flex;justify-content:flex-end;gap:8px}
.v3d-prominent{background:#F5C518!important;color:#1E1F22!important;border-color:#F5C518!important}
.v3d-flat:disabled{opacity:.45}
.v3d-switch{appearance:none;width:26px;height:15px;border-radius:8px;background:#4A4B50;position:relative;margin:0}
.v3d-switch:checked{background:#F5C518}
.v3d-switch::after{content:"";position:absolute;left:2px;top:2px;width:11px;height:11px;border-radius:50%;background:#fff;transition:left .12s}
.v3d-switch:checked::after{left:13px}
`;
  document.head.append(css);
}
