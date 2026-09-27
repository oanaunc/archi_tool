// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Family Editor (FamilyEditorPanel.swift, FAMILY Edit): families list, header (name, category, Revert, Apply, … menu),
// Parameters / Forms / Types / Planes & Profiles tabs, and the preview column (axonometric flat-shaded preview, type
// picker, flex values, problems). Edits change a draft; Apply writes it as one undo step (family.apply).
import type { App } from "../app";
import { h, clear, button, iconButton, field, segmented, picker, checkbox, spacer, ToolWindow, ico, help, showMenu, fmt, type MenuItem } from "./ui";
import { decodeMeshes } from "./mesh-preview";

type Dict = Record<string, string>;
interface Param { name: string; kind: string; value: string; formula?: string | null; instance: boolean; min?: number | null; max?: number | null; [k: string]: any }
interface Form { name: string; kind: string; x: string; y: string; z: string; rotation: string; dims: Dict; void: boolean; path: string[][]; profile?: string | null; profile2?: string | null;
  family?: string | null; material?: string | null; visible?: string | null; arrayCount?: string | null; arrayDX?: string | null; arrayDY?: string | null; arrayDZ?: string | null; [k: string]: any }
interface Family { name: string; category: string; description: string; parameters: Param[]; forms: Form[]; types: Record<string, Dict>; referencePlanes: { name: string; axis: string; offset: string }[];
  profiles: { name: string; points: string[][]; width?: string | null; height?: string | null }[]; symbolic: any[]; [k: string]: any }

const TEMPLATES = ["Generic Model", "Door", "Window", "Furniture"];
const CATEGORIES = ["Generic Model", "Furniture", "Door", "Window", "Casework", "Lighting", "Plumbing", "Profile", "Specialty"];
const BUILTIN_PROFILES = ["rect", "round", "I-beam", "channel", "angle", "tee", "tube", "pipe"];
const NUMERIC = new Set(["length", "angle", "number", "integer", "area", "volume"]);

export function defaultDims(k: string): Dict {
  switch (k) {
    case "box": return { width: "100", depth: "100", height: "100" };
    case "cylinder": return { radius: "50", height: "100" };
    case "extrusion": return { height: "100", width: "100", depth: "100" };
    case "sweep": return { width: "50", height: "50" };
    case "revolve": return { angle: "360", width: "100", height: "100" };
    case "blend": return { height: "100", width: "100", depth: "100", width2: "50", depth2: "50" };
    case "sweptBlend": return { width: "50", height: "50", width2: "25", height2: "25" };
    default: return {};
  }
}
/** Replaces a whole identifier (case-insensitive) in an expression (FamilyEditorModel.replaceIdentifier). */
export function replaceIdentifier(old: string, nu: string, s: string): string {
  let out = "", cur = "";
  const flush = () => { out += cur.toLowerCase() === old.toLowerCase() ? nu : cur; cur = ""; };
  for (const c of s) { if (/[\p{L}\p{N}_]/u.test(c) || (c === "." && cur)) cur += c; else { flush(); out += c; } }
  flush();
  return out;
}
export function splitTop(s: string, sep: string): string[] {
  const out: string[] = []; let cur = "", depth = 0;
  for (const c of s) { if (c === "(") depth++; else if (c === ")") depth = Math.max(0, depth - 1); if (c === sep && depth === 0) { out.push(cur); cur = ""; } else cur += c; }
  out.push(cur);
  return out;
}
export const pointsText = (pts: string[][]) => pts.map((p) => p.join(", ")).join("; ");
export function parsePoints(s: string, dims: number): string[][] | null {
  const out: string[][] = [];
  for (const part of splitTop(s, ";")) {
    const t = part.trim(); if (!t) continue;
    const c = splitTop(t, ",").map((x) => x.trim());
    if (c.length !== dims || c.some((x) => !x)) return null;
    out.push(c);
  }
  return out;
}
const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v));
const same = (a: any, b: any) => JSON.stringify(sortKeys(a)) === JSON.stringify(sortKeys(b));
function sortKeys(v: any): any { if (Array.isArray(v)) return v.map(sortKeys); if (v && typeof v === "object") { const o: any = {}; for (const k of Object.keys(v).sort()) if (v[k] !== null && v[k] !== undefined) o[k] = sortKeys(v[k]); return o; } return v; }

/** Working copy of a document family (FamilyEditorModel). */
export class FamilyEditorModel {
  draft: Family | null = null;
  original: Family | null = null;
  originalName: string | null = null;
  previewType: string | null = null;
  flex: Dict = {};
  selectedForm: number | null = null;
  message = "";
  load(d: Family) { this.draft = clone(d); this.original = clone(d); this.originalName = d.name; this.previewType = Object.keys(d.types ?? {}).sort()[0] ?? null; this.flex = {}; this.selectedForm = d.forms.length ? 0 : null; this.message = ""; }
  newFamily(d: Family, template: string) { this.draft = d; this.original = null; this.originalName = null; this.previewType = Object.keys(d.types ?? {}).sort()[0] ?? null; this.flex = {}; this.selectedForm = d.forms.length ? 0 : null; this.message = `New ${template.toLowerCase()} family — Apply to add it to the drawing.`; }
  get dirty() { return !!this.draft && (!this.original || !same(this.draft, this.original)); }
  addParameter(kind = "length") {
    const d = this.draft!; let n = "Param", k = 1;
    const has = (x: string) => d.parameters.some((p) => p.name.toLowerCase() === x.toLowerCase());
    while (has(k === 1 ? n : `${n}${k}`)) k++;
    if (k > 1) n += k;
    d.parameters.push({ name: n, kind, value: NUMERIC.has(kind) ? "0" : "", formula: null, instance: true, min: null, max: null });
  }
  removeParameter(i: number) { const d = this.draft!; const name = d.parameters[i]?.name; if (name === undefined) return; d.parameters.splice(i, 1); for (const t of Object.keys(d.types)) delete d.types[t][name]; }
  renameParameter(i: number, nu: string) {
    const d = this.draft!; const p = d.parameters[i]; if (!p) return;
    const old = p.name, n = nu.trim();
    if (!n || n === old || (d.parameters.some((q) => q.name.toLowerCase() === n.toLowerCase()) && n.toLowerCase() !== old.toLowerCase())) return;
    const sub = (s: string) => replaceIdentifier(old, n, s);
    const subO = (s?: string | null) => (s === null || s === undefined ? s : sub(s));
    p.name = n;
    for (const q of d.parameters) q.formula = subO(q.formula);
    for (const f of d.forms) {
      f.x = sub(f.x); f.y = sub(f.y); f.z = sub(f.z); f.rotation = sub(f.rotation);
      for (const k of Object.keys(f.dims)) f.dims[k] = sub(f.dims[k]);
      f.path = (f.path ?? []).map((pt) => pt.map(sub));
      f.visible = subO(f.visible); f.arrayCount = subO(f.arrayCount); f.arrayDX = subO(f.arrayDX); f.arrayDY = subO(f.arrayDY); f.arrayDZ = subO(f.arrayDZ);
      if (f.material === "=" + old) f.material = "=" + n;
    }
    for (const pr of d.profiles) { pr.points = pr.points.map((pt) => pt.map(sub)); pr.width = subO(pr.width); pr.height = subO(pr.height); }
    for (const pl of d.referencePlanes) pl.offset = sub(pl.offset);
    for (const t of Object.keys(d.types)) if (old in d.types[t]) { d.types[t][n] = d.types[t][old]; delete d.types[t][old]; }
  }
  addForm(kind: string) {
    const d = this.draft!;
    const f: Form = { name: `${kind[0].toUpperCase() + kind.slice(1)} ${d.forms.length + 1}`, kind, x: "0", y: "0", z: "0", rotation: "0", dims: defaultDims(kind), void: false, path: [] };
    if (kind === "extrusion" || kind === "revolve" || kind === "blend") f.profile = d.profiles[0]?.name ?? "rect";
    if (kind === "sweep" || kind === "sweptBlend") { f.profile = d.profiles[0]?.name ?? "round"; f.path = [["0", "0", "0"], ["0", "0", "500"]]; }
    d.forms.push(f);
    this.selectedForm = d.forms.length - 1;
  }
  removeForm(i: number) { const d = this.draft!; d.forms.splice(i, 1); this.selectedForm = d.forms.length ? Math.min(i, d.forms.length - 1) : null; }
  duplicateForm(i: number) { const d = this.draft!; const f = clone(d.forms[i]); f.name += " copy"; d.forms.splice(i + 1, 0, f); this.selectedForm = i + 1; }
  moveForm(i: number, by: number) { const d = this.draft!; const j = i + by; if (j < 0 || j >= d.forms.length) return; [d.forms[i], d.forms[j]] = [d.forms[j], d.forms[i]]; this.selectedForm = j; }
  setKind(i: number, k: string) { const f = this.draft!.forms[i]; f.kind = k; for (const [key, v] of Object.entries(defaultDims(k))) if (f.dims[key] === undefined) f.dims[key] = v; }
  addType(name: string) {
    const d = this.draft!; const n = name.trim();
    if (!n || Object.keys(d.types).some((t) => t.toLowerCase() === n.toLowerCase())) { this.message = "Type names must be unique."; return; }
    const src = (this.previewType && d.types[this.previewType]) || {};
    const vals: Dict = {};
    for (const p of d.parameters) if (!p.formula) vals[p.name] = src[p.name] ?? p.value;
    d.types[n] = vals; this.previewType = n;
  }
  removeType(t: string) { const d = this.draft!; delete d.types[t]; if (this.previewType === t) this.previewType = Object.keys(d.types).sort()[0] ?? null; }
  renameType(old: string, nu: string) {
    const d = this.draft!; const n = nu.trim(); const v = d.types[old];
    if (!v || !n || n === old || d.types[n]) return;
    delete d.types[old]; d.types[n] = v; if (this.previewType === old) this.previewType = n;
  }
  setTypeValue(t: string, p: string, v: string) { const d = this.draft!; if (!d.types[t]) return; if (v) d.types[t][p] = v; else delete d.types[t][p]; }
  addPlane(axis: string) { const d = this.draft!; let k = d.referencePlanes.length + 1; while (d.referencePlanes.some((p) => p.name === `Plane${k}`)) k++; d.referencePlanes.push({ name: `Plane${k}`, axis, offset: "0" }); }
  addProfile() { const d = this.draft!; let k = d.profiles.length + 1; while (d.profiles.some((p) => p.name.toLowerCase() === `profile${k}`)) k++; d.profiles.push({ name: `Profile${k}`, points: [["0", "0"], ["100", "0"], ["100", "100"], ["0", "100"]] }); }
}

// ---- preview projection (FamilyPreviewProjection) ----

export function paintFamilyPreview(cv: HTMLCanvasElement, meshes: any[], yaw: number, pitch = Math.PI / 5, margin = 12) {
  const w = cv.clientWidth || 290, hh = cv.clientHeight || 230, dpr = devicePixelRatio || 1;
  cv.width = w * dpr; cv.height = hh * dpr;
  const g = cv.getContext("2d")!;
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.fillStyle = "#1B1C1F"; g.fillRect(0, 0, w, hh);
  const tris = decodeMeshes(meshes ?? []);
  if (!tris.length) { g.fillStyle = "#8E8E93"; g.font = "12px system-ui, 'Segoe UI', sans-serif"; g.textAlign = "center"; g.fillText("No geometry", w / 2, hh / 2); return; }
  const cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(pitch), sp = Math.sin(pitch);
  const view = (p: number[]) => { const x = p[0] * cy - p[1] * sy, y = p[0] * sy + p[1] * cy; return [x, y * sp + p[2] * cp, y * cp - p[2] * sp]; };
  const L = [-0.4, -0.6, 0.7], ll = Math.hypot(L[0], L[1], L[2]);
  const raw = tris.map((t) => {
    const u = [t.b[0] - t.a[0], t.b[1] - t.a[1], t.b[2] - t.a[2]], v = [t.c[0] - t.a[0], t.c[1] - t.a[1], t.c[2] - t.a[2]];
    const n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]], nl = Math.hypot(n[0], n[1], n[2]);
    const shade = nl > 1e-12 ? 0.45 + 0.55 * Math.abs((n[0] * L[0] + n[1] * L[1] + n[2] * L[2]) / nl / ll) : 0.6;
    return { p: [view(t.a), view(t.b), view(t.c)], color: t.color, opacity: t.opacity, shade };
  });
  let lo = [Infinity, Infinity], hi = [-Infinity, -Infinity];
  for (const t of raw) for (const p of t.p) { lo = [Math.min(lo[0], p[0]), Math.min(lo[1], p[1])]; hi = [Math.max(hi[0], p[0]), Math.max(hi[1], p[1])]; }
  const ww = Math.max(hi[0] - lo[0], 1e-9), wh = Math.max(hi[1] - lo[1], 1e-9);
  const s = Math.min((w - 2 * margin) / ww, (hh - 2 * margin) / wh);
  const ox = (w - ww * s) / 2, oy = (hh - wh * s) / 2;
  const pt = (p: number[]) => [ox + (p[0] - lo[0]) * s, hh - (oy + (p[1] - lo[1]) * s)];
  raw.sort((a, b) => (b.p[0][2] + b.p[1][2] + b.p[2][2]) - (a.p[0][2] + a.p[1][2] + a.p[2][2]));
  g.lineWidth = 0.4;
  for (const t of raw) {
    const [a, b, c] = t.p.map(pt);
    const col = `rgba(${Math.round(t.color[0] * t.shade)},${Math.round(t.color[1] * t.shade)},${Math.round(t.color[2] * t.shade)},${Math.max(0.35, t.opacity)})`;
    g.beginPath(); g.moveTo(a[0], a[1]); g.lineTo(b[0], b[1]); g.lineTo(c[0], c[1]); g.closePath();
    g.fillStyle = col; g.fill(); g.strokeStyle = col; g.stroke();
  }
}

/** Family name of an element JSON (component geometry or the `family` prop), lower-cased. */
function familyOf(e: any): string {
  const walk = (v: any, depth: number): string | null => {
    if (!v || typeof v !== "object" || depth > 4) return null;
    if (typeof v.family === "string") return v.family;
    for (const k of Object.keys(v)) { const r = walk(v[k], depth + 1); if (r) return r; }
    return null;
  };
  return String(e?.props?.family ?? walk(e?.geometry, 0) ?? "").toLowerCase();
}

// ---- window ----

const model = new FamilyEditorModel();
let docKey: string | null = null;

export async function showFamilyEditor(app: App, family?: string | null) {
  const key = app.info?.path ?? app.info?.title ?? "";
  if (docKey !== key) { docKey = key; Object.assign(model, new FamilyEditorModel()); }
  const list = await app.tryCall("family.list");
  const f = family || list?.current || list?.families?.[0]?.name;
  if (f && (model.originalName?.toLowerCase() !== f.toLowerCase() || !model.draft)) {
    const d = await app.tryCall("family.get", { name: f });
    if (d) model.load(d);
  }
  ToolWindow.show("familyEditor", "Family Editor", { w: 980, h: 640, minW: 820, minH: 480 }, (w) => { new FamilyEditorView(app, w.body); });
}

let familyView: FamilyEditorView | null = null;
let familyHooked = false;

class FamilyEditorView {
  private tab = "Parameters";
  private yaw = -Math.PI / 6;
  private info: any = { families: [], parameterKinds: [], formKinds: [], materials: [] };
  private evaluated: any = null;
  private evalTimer = 0;
  private listCol = h("div", { class: "pb-col", style: { width: "190px", flex: "none", gap: "4px" } });
  private mid = h("div", { class: "pb-col", style: { flex: "1", minWidth: "430px", padding: "8px", gap: "6px", minHeight: "0" } });
  private right = h("div", { class: "pb-col", style: { width: "290px", flex: "none", padding: "8px", gap: "6px", minHeight: "0" } });
  private cv = h("canvas", { style: { width: "100%", height: "230px", borderRadius: "6px", display: "block", cursor: "ew-resize" } }) as HTMLCanvasElement;
  constructor(private app: App, host: HTMLElement) {
    host.append(h("div", { class: "pb-row", style: { alignItems: "stretch", flex: "1", minHeight: "0", gap: "0" } }, this.listCol, h("div", { class: "pb-vsep" }), this.mid, h("div", { class: "pb-vsep" }), this.right));
    let drag: number | null = null;
    this.cv.addEventListener("pointerdown", (e) => { drag = e.clientX; this.cv.setPointerCapture(e.pointerId); });
    this.cv.addEventListener("pointermove", (e) => { if (drag === null) return; this.yaw = -Math.PI / 6 + (e.clientX - drag) / 120; this.paint(); });
    this.cv.addEventListener("pointerup", () => { drag = null; });
    this.reload();
    familyView = this;
    if (!familyHooked) { familyHooked = true; app.on("doc", () => { if (ToolWindow.isOpen("familyEditor")) void familyView?.reload(false); }); }
  }
  async reload(all = true) {
    this.info = (await this.app.tryCall("family.list")) ?? this.info;
    if (model.originalName && !model.dirty) { const d = await this.app.tryCall("family.get", { name: model.originalName }); if (d) model.load(d); }
    this.renderList();
    if (all) this.render();
  }
  private changed(full = false) {
    if (full) this.render(); else this.renderHeaderState();
    clearTimeout(this.evalTimer);
    this.evalTimer = window.setTimeout(() => this.evaluate(), 150);
  }
  private async evaluate() {
    if (!model.draft) return;
    this.evaluated = await this.app.tryCall("family.evaluate", { draft: model.draft, original: model.originalName, type: model.previewType, flex: model.flex });
    this.renderRight();
  }
  private paint() { paintFamilyPreview(this.cv, this.evaluated?.meshes ?? [], this.yaw); }

  private confirmDiscard(): boolean { return !model.dirty || confirm(`Discard the changes to ${model.draft?.name ?? "this family"}?`); }

  private renderList() {
    clear(this.listCol);
    const listEl = h("div", { class: "pb-scroll", style: { flex: "1" } });
    for (const f of this.info.families ?? []) {
      const row = h("div", { class: "pb-list-row soft", style: { gap: "6px", padding: "4px 8px" } },
        h("span", { style: { color: model.originalName === f.name ? "var(--accent)" : "var(--dim)", display: "flex" } }, ico("cube.box", 14)),
        h("div", { class: "pb-col", style: { gap: "0", minWidth: "0" } }, h("div", { style: { whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }, text: f.name }),
          h("div", { class: "pb-small pb-dim", text: `${f.category} · ${f.instances} placed` })));
      row.addEventListener("click", async () => { if (!this.confirmDiscard()) return; const d = await this.app.tryCall("family.get", { name: f.name }); if (d) { model.load(d); this.renderList(); this.render(); } });
      listEl.append(row);
    }
    const newBtn = button("New from Template", { compact: true });
    newBtn.addEventListener("click", () => showMenu(TEMPLATES.map((t) => ({ title: t, action: async () => {
      if (!this.confirmDiscard()) return;
      const d = await this.app.tryCall("family.template", { template: t });
      if (d) { model.newFamily(d, t); this.renderList(); this.render(); }
    } })), newBtn));
    this.listCol.append(h("div", { style: { fontWeight: "600", padding: "8px 8px 0" }, text: "Families" }), listEl, h("div", { style: { padding: "8px" } }, newBtn));
  }

  private applyBtn: HTMLButtonElement | null = null;
  private revertBtn: HTMLButtonElement | null = null;
  private msgEl = h("div", { class: "pb-small pb-dim" });
  private renderHeaderState() {
    if (this.applyBtn) this.applyBtn.disabled = !model.dirty;
    if (this.revertBtn) this.revertBtn.disabled = !model.dirty;
    this.msgEl.textContent = model.message;
    this.msgEl.style.display = model.message ? "" : "none";
  }

  private render() {
    clear(this.mid);
    const d = model.draft;
    if (!d) {
      this.mid.append(h("div", { class: "pb-empty", style: { flex: "1" } }, h("div", { class: "pb-dim", text: "Select a family or create one from a template." })));
      clear(this.right); this.right.style.display = "none";
      return;
    }
    this.right.style.display = "";
    const cats = [...new Set([...CATEGORIES, d.category])].sort();
    this.revertBtn = button("Revert", { compact: true, onClick: async () => {
      if (model.originalName) { const o = await this.app.tryCall("family.get", { name: model.originalName }); if (o) model.load(o); } else model.draft = null;
      this.render(); this.evaluate();
    } });
    this.applyBtn = button("Apply", { compact: true, prominent: true, onClick: () => this.apply() });
    const more = iconButton("ellipsis.circle", "More", () => {
      const items: MenuItem[] = [
        { title: "Place in Drawing", disabled: d.name.includes(" "), action: async () => {
          if (model.dirty && !(await this.apply())) return;
          if (model.originalName) { await this.app.tryCall("doc.edit", { label: "Current Family", ops: [{ op: "setVariable", name: "CURRENTFAMILY", value: model.originalName }] }); this.app.runCommand("FAMILY Place " + model.originalName); }
        } },
        { title: "Select Instances", disabled: !model.originalName, action: async () => {
          const els = (await this.app.tryCall("script.call", { fn: "elements", args: [] })) ?? [];
          const n = model.originalName!.toLowerCase();
          const ids = (Array.isArray(els) ? els : els.elements ?? []).filter((e: any) => familyOf(e) === n).map((e: any) => e.id);
          await this.app.tryCall("select.set", { ids }); await this.app.refresh(["selection"]);
        } },
        { separator: true },
        { title: "Delete Family", action: async () => {
          if (!model.originalName) { model.draft = null; this.render(); return; }
          try { const r = await this.app.call("family.delete", { name: model.originalName }); model.draft = null; model.originalName = null; model.original = null; model.message = r?.message ?? ""; await this.app.refresh(["document"]); this.reload(); }
          catch (e: any) { model.message = e?.message ?? String(e); this.renderHeaderState(); }
        } },
      ];
      showMenu(items, more);
    });
    this.mid.append(
      h("div", { class: "pb-row" }, field({ value: d.name, placeholder: "Name", width: 170, onInput: (v) => { d.name = v; this.changed(); } }),
        picker(cats, d.category, (v) => { d.category = v; this.changed(); }, 130), spacer(), this.revertBtn, this.applyBtn, more),
      field({ value: d.description ?? "", placeholder: "Description", onInput: (v) => { d.description = v; this.changed(); } }), this.msgEl);
    this.renderHeaderState();
    const seg = segmented(["Parameters", "Forms", "Types", "Planes & Profiles"], this.tab, (v) => { this.tab = v; this.render(); });
    const scroll = h("div", { class: "pb-scroll", style: { flex: "1" } });
    this.mid.append(seg, scroll);
    if (this.tab === "Forms") this.forms(scroll, d);
    else if (this.tab === "Types") this.types(scroll, d);
    else if (this.tab === "Planes & Profiles") this.planes(scroll, d);
    else this.parameters(scroll, d);
    this.renderRight();
    if (!this.evaluated) this.evaluate();
  }

  private async apply(): Promise<boolean> {
    if (!model.draft) return false;
    try {
      const r = await this.app.call("family.apply", { draft: model.draft, original: model.originalName });
      model.draft.name = r.name; model.originalName = r.name; model.original = clone(model.draft); model.message = r.message;
      await this.app.refresh(["document"]);
      this.reload();
      return true;
    } catch (e: any) { model.message = e?.message ?? String(e); this.renderHeaderState(); return false; }
  }

  private parameters(host: HTMLElement, d: Family) {
    const hdr = (t: string, w?: number) => h("span", { style: w ? { width: w + "px", flex: "none" } : { flex: "1" }, text: t });
    host.append(h("div", { class: "pb-row pb-small pb-dim", style: { gap: "4px" } }, hdr("Name", 92), hdr("Kind", 78), hdr("Value", 70), hdr("Formula"),
      h("span", { style: { width: "34px", textAlign: "center" }, text: "Inst." }), hdr("Min", 42), hdr("Max", 42), h("span", { style: { width: "18px" } })));
    d.parameters.forEach((p, i) => {
      const value = field({ value: p.value, width: 70, onInput: (v) => { p.value = v; this.changed(); } });
      value.disabled = !!p.formula;
      const inst = h("input", { type: "checkbox" }) as HTMLInputElement;
      inst.checked = p.instance; help(inst, "Instance parameter (off = type parameter)");
      inst.addEventListener("change", () => { p.instance = inst.checked; this.changed(); });
      const num = (v: number | null | undefined, set: (x: number | null) => void) => field({ value: v === null || v === undefined ? "" : fmt(v, 4), width: 42, onInput: (s) => { const x = parseFloat(s); set(s.trim() && isFinite(x) ? x : null); this.changed(); } });
      host.append(h("div", { class: "pb-row", style: { gap: "4px", marginTop: "3px" } },
        field({ value: p.name, width: 92, onCommit: (v) => { model.renameParameter(i, v); this.changed(true); } }),
        picker(this.info.parameterKinds ?? [], p.kind, (v) => { p.kind = v; this.changed(); }, 78),
        value,
        field({ value: p.formula ?? "", placeholder: "free", flex: true, onInput: (v) => { p.formula = v || null; value.disabled = !!v; this.changed(); } }),
        h("span", { style: { width: "34px", display: "flex", justifyContent: "center" } }, inst),
        num(p.min, (x) => { p.min = x; }), num(p.max, (x) => { p.max = x; }),
        iconButton("minus.circle", "Remove", () => { model.removeParameter(i); this.changed(true); })));
    });
    const add = button("Add Parameter", { compact: true });
    add.addEventListener("click", () => showMenu((this.info.parameterKinds ?? []).map((k: string) => ({ title: k, action: () => { model.addParameter(k); this.changed(true); } })), add));
    host.append(h("div", { style: { paddingTop: "4px" } }, add));
  }

  private forms(host: HTMLElement, d: Family) {
    d.forms.forEach((f, i) => {
      const r = h("div", { class: "pb-list-row soft" + (model.selectedForm === i ? " sel" : ""), style: { gap: "6px", padding: "4px" } },
        h("span", { style: { color: model.selectedForm === i ? "var(--accent)" : "var(--dim)", display: "flex" } }, ico(f.void ? "cube.transparent" : f.kind === "nested" ? "square.on.square" : "cube.fill", 13)),
        h("span", { text: f.name || f.kind }),
        h("span", { class: "pb-small pb-dim", text: f.kind + (f.void ? " · void" : "") + (f.arrayCount && f.arrayCount !== "1" ? " · array" : "") }), spacer(),
        iconButton("chevron.up", "Move up", () => { model.moveForm(i, -1); this.changed(true); }, { disabled: i === 0 }),
        iconButton("chevron.down", "Move down", () => { model.moveForm(i, 1); this.changed(true); }, { disabled: i === d.forms.length - 1 }),
        iconButton("plus.square.on.square", "Duplicate", () => { model.duplicateForm(i); this.changed(true); }),
        iconButton("minus.circle", "Remove", () => { model.removeForm(i); this.changed(true); }));
      r.addEventListener("click", (e) => { if ((e.target as HTMLElement).closest("button")) return; model.selectedForm = i; this.render(); });
      host.append(r);
    });
    const add = button("Add Form", { compact: true });
    add.addEventListener("click", () => showMenu((this.info.formKinds ?? []).map((k: string) => ({ title: k, action: () => { model.addForm(k); this.changed(true); } })), add));
    host.append(h("div", { style: { padding: "4px 0" } }, add));
    const i = model.selectedForm;
    if (i === null || !d.forms[i]) return;
    const f = d.forms[i];
    host.append(h("div", { class: "pb-hsep", style: { margin: "4px 0" } }));
    const fld = (label: string, key: string, width = 90, opt = false, ph = "") => h("div", { class: "pb-row", style: { gap: "3px" } }, h("span", { class: "pb-dim", text: label }),
      field({ value: f[key] ?? "", placeholder: ph, width, onInput: (v) => { f[key] = opt && !v ? null : v; this.changed(); } }));
    const voidBox = checkbox("Void", f.void, (v) => { f.void = v; this.changed(); }, "Void forms cut the solid forms");
    host.append(h("div", { class: "pb-col", style: { gap: "5px" } },
      h("div", { class: "pb-row" }, fld("Name", "name", 140), picker(this.info.formKinds ?? [], f.kind, (v) => { model.setKind(i, v); this.changed(true); }, 110), voidBox),
      h("div", { class: "pb-row" }, fld("X", "x"), fld("Y", "y"), fld("Z", "z")),
      h("div", { class: "pb-row" }, fld("Rotation°", "rotation", 60), fld("Visible if", "visible", 150, true, "always")),
      h("div", { style: { fontWeight: "600" }, text: "Dimensions" })));
    const keys = [...new Set([...Object.keys(f.dims), ...Object.keys(defaultDims(f.kind))])].sort();
    const grid = h("div", { style: { display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(150px, 1fr))", gap: "4px" } });
    for (const k of keys) grid.append(h("div", { class: "pb-row", style: { gap: "3px" } }, h("span", { class: "pb-dim", style: { width: "48px", textAlign: "right" }, text: k }),
      field({ value: f.dims[k] ?? "", width: 90, onInput: (v) => { if (v) f.dims[k] = v; else delete f.dims[k]; this.changed(); } })));
    host.append(grid);
    const profileMenu = (title: string, cur: string | null | undefined, set: (v: string | null) => void) => {
      const opts = [{ value: "", label: "—" }, ...d.profiles.map((p) => ({ value: p.name, label: p.name })), ...BUILTIN_PROFILES.map((p) => ({ value: p, label: p }))];
      if (cur && !opts.some((o) => o.value === cur)) opts.push({ value: cur, label: cur });
      return h("div", { class: "pb-row", style: { gap: "4px" } }, h("span", { text: title }), picker(opts, cur ?? "", (v) => { set(v || null); this.changed(); }, 140));
    };
    if (["extrusion", "sweep", "revolve", "blend", "sweptBlend"].includes(f.kind)) {
      host.append(h("div", { class: "pb-row", style: { marginTop: "5px" } }, profileMenu("Profile", f.profile, (v) => { f.profile = v; }),
        f.kind === "blend" || f.kind === "sweptBlend" ? profileMenu("End profile", f.profile2, (v) => { f.profile2 = v; }) : null));
    }
    if (f.kind === "sweep" || f.kind === "sweptBlend") {
      host.append(h("div", { class: "pb-row", style: { gap: "3px", marginTop: "5px" } }, h("span", { class: "pb-dim", text: "Path x,y,z;…" }),
        field({ value: pointsText(f.path ?? []), flex: true, onCommit: (v) => { const p = parsePoints(v, 3); if (p && p.length >= 2) { f.path = p; this.changed(); } else { model.message = "A path needs at least two x,y,z points."; this.renderHeaderState(); } } })));
    }
    if (f.kind === "nested") {
      const opts = [{ value: "", label: "—" }, ...(this.info.families ?? []).map((x: any) => x.name).filter((n: string) => n !== d.name).map((n: string) => ({ value: n, label: n })),
        ...d.parameters.filter((p) => p.kind === "familyType").map((p) => ({ value: "=" + p.name, label: "=" + p.name }))];
      host.append(h("div", { class: "pb-row", style: { marginTop: "5px" } }, h("span", { text: "Family" }), picker(opts, f.family ?? "", (v) => { f.family = v || null; this.changed(); }, 180)));
    }
    const mats = [{ value: "", label: "By element" }, ...[...(this.info.materials ?? [])].sort().map((m: string) => ({ value: m, label: m })),
      ...d.parameters.filter((p) => p.kind === "material").map((p) => ({ value: "=" + p.name, label: "=" + p.name }))];
    if (f.material && !mats.some((m) => m.value === f.material)) mats.push({ value: f.material, label: f.material });
    host.append(h("div", { class: "pb-row", style: { marginTop: "5px" } }, h("span", { text: "Material" }), picker(mats, f.material ?? "", (v) => { f.material = v || null; this.changed(); }, 180)),
      h("div", { class: "pb-row", style: { marginTop: "5px" } }, fld("Array ×", "arrayCount", 44, true, "1"), fld("dX", "arrayDX", 70, true), fld("dY", "arrayDY", 70, true), fld("dZ", "arrayDZ", 70, true)));
  }

  private types(host: HTMLElement, d: Family) {
    const types = Object.keys(d.types).sort();
    const params = d.parameters.filter((p) => !p.formula);
    if (!types.length) host.append(h("div", { class: "pb-dim", text: "No types: instances use the parameter defaults. Add a type to build a types table." }));
    const table = h("div", { class: "pb-col", style: { gap: "3px", overflowX: "auto" } });
    table.append(h("div", { class: "pb-row", style: { gap: "4px" } }, h("span", { class: "pb-dim", style: { width: "100px", flex: "none" }, text: "Parameter" }),
      ...types.map((t) => h("div", { class: "pb-row", style: { gap: "2px", width: "110px", flex: "none" } },
        field({ value: t, flex: true, onCommit: (v) => { model.renameType(t, v); this.changed(true); } }), iconButton("xmark.circle", "Remove type", () => { model.removeType(t); this.changed(true); })))));
    for (const p of params) table.append(h("div", { class: "pb-row", style: { gap: "4px" } }, h("span", { style: { width: "100px", flex: "none", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }, text: p.name + (p.instance ? "" : " (type)") }),
      ...types.map((t) => field({ value: d.types[t]?.[p.name] ?? "", placeholder: p.value, width: 110, onInput: (v) => { model.setTypeValue(t, p.name, v); this.changed(); } }))));
    host.append(table);
    let nt = "";
    const addBtn = button("Add Type", { compact: true, disabled: true, onClick: () => { model.addType(nt); this.changed(true); } });
    host.append(h("div", { class: "pb-row", style: { marginTop: "4px" } }, field({ placeholder: "New type name", width: 160, onInput: (v) => { nt = v; addBtn.disabled = !v.trim(); } }), addBtn));
  }

  private planes(host: HTMLElement, d: Family) {
    host.append(h("div", { style: { fontWeight: "600" }, text: "Reference planes" }),
      h("div", { class: "pb-small pb-dim", text: "Use a plane's name in any expression; forms drawn to it follow the plane when parameters flex." }));
    d.referencePlanes.forEach((pl, i) => host.append(h("div", { class: "pb-row", style: { gap: "4px", marginTop: "4px" } },
      field({ value: pl.name, width: 100, onInput: (v) => { pl.name = v; this.changed(); } }),
      picker([{ value: "x", label: "⟂ X" }, { value: "y", label: "⟂ Y" }, { value: "z", label: "⟂ Z" }], pl.axis, (v) => { pl.axis = v; this.changed(); }, 70),
      field({ value: pl.offset, placeholder: "offset", flex: true, onInput: (v) => { pl.offset = v; this.changed(); } }),
      iconButton("minus.circle", "Remove", () => { d.referencePlanes.splice(i, 1); this.changed(true); }))));
    host.append(h("div", { class: "pb-row", style: { marginTop: "5px" } }, ...["x", "y", "z"].map((a) => button(`Add ⟂ ${a.toUpperCase()}`, { compact: true, onClick: () => { model.addPlane(a); this.changed(true); } }))),
      h("div", { class: "pb-hsep", style: { margin: "6px 0" } }), h("div", { style: { fontWeight: "600" }, text: "Profiles" }),
      h("div", { class: "pb-small pb-dim", text: "Vertices as x, y; x, y … (expressions allowed)." }));
    d.profiles.forEach((pr, i) => host.append(h("div", { class: "pb-col", style: { gap: "2px", marginTop: "4px" } },
      h("div", { class: "pb-row" }, field({ value: pr.name, width: 120, onInput: (v) => { pr.name = v; this.changed(); } }), spacer(), iconButton("minus.circle", "Remove", () => { d.profiles.splice(i, 1); this.changed(true); })),
      field({ value: pointsText(pr.points), onCommit: (v) => { const p = parsePoints(v, 2); if (p && p.length >= 3) { pr.points = p; this.changed(); } else { model.message = "A profile needs at least three x, y points."; this.renderHeaderState(); } } }))));
    host.append(h("div", { style: { marginTop: "5px" } }, button("Add Profile", { compact: true, onClick: () => { model.addProfile(); this.changed(true); } })));
  }

  private renderRight() {
    const d = model.draft;
    if (!d) return;
    clear(this.right);
    const r = this.evaluated;
    const b = r?.bounds;
    this.right.append(this.cv, h("div", { class: "pb-mono", text: b ? `Size ${fmt(b[1][0] - b[0][0], 0)} × ${fmt(b[1][1] - b[0][1], 0)} × ${fmt(b[1][2] - b[0][2], 0)}` : "Empty" }));
    requestAnimationFrame(() => this.paint());
    const types = Object.keys(d.types).sort();
    if (types.length) this.right.append(h("div", { class: "pb-row" }, h("span", { text: "Type" }),
      picker([{ value: "", label: "Defaults" }, ...types.map((t) => ({ value: t, label: t }))], model.previewType ?? "", (v) => { model.previewType = v || null; this.evaluate(); })));
    this.right.append(h("div", { style: { fontWeight: "600" }, text: "Flex (preview only)" }));
    const sc = h("div", { class: "pb-scroll pb-col", style: { flex: "1", gap: "3px" } });
    const val = (n: string) => { const k = n.toLowerCase(); const v = r?.values?.[k]; return v !== undefined ? fmt(v, 3) : r?.text?.[k] ?? ""; };
    for (const p of d.parameters) {
      const row = h("div", { class: "pb-row", style: { gap: "4px" } }, h("span", { style: { width: "90px", flex: "none", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }, text: p.name }));
      if (!p.formula && p.instance) row.append(field({ value: model.flex[p.name] ?? "", placeholder: val(p.name), flex: true, onCommit: (v) => { if (v.trim()) model.flex[p.name] = v; else delete model.flex[p.name]; this.evaluate(); } }));
      else row.append(h("span", { class: "pb-mono pb-dim", text: val(p.name) || "—" }), h("span", { class: "pb-small pb-faint", text: p.formula ? "= formula" : "type" }));
      sc.append(row);
    }
    if (Object.keys(model.flex).length) sc.append(h("div", {}, button("Reset Flex", { compact: true, onClick: () => { model.flex = {}; this.evaluate(); } })));
    this.right.append(sc);
    const probs: string[] = r?.problems ?? [];
    if (probs.length) this.right.append(h("div", { class: "pb-col", style: { gap: "2px" } }, ...probs.slice(0, 6).map((p) => h("div", { class: "pb-small", style: { color: "var(--danger, #E5534B)" }, text: "⚠ " + p }))));
  }
}
