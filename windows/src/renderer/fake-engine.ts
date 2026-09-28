// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Fixture engine: lets the renderer run as a plain web page (Chromium + Playwright tests, design review) without
// archi-engine.exe. It replays recorded engine traffic (session.jsonl: {method, params, result} per line) and
// per-method fixture files (<method>.json, e.g. view.drawList.json from build/engine-fixtures), and simulates just
// enough of the engine (LINE, CIRCLE, RECTANG, ERASE, selection, grips, undo, system variables, panels) to exercise
// the UI. It is never used inside the Electron app.
import { snapPoint, type Notification, type PromptState } from "../shared/protocol";
import type { Engine } from "./engine";
import { decodeDrawList, pick as pickEntry, Entry } from "./canvas/drawitems";
import { fakeDialogCall } from "./dialogs/fake-dialogs";
import { fakeOutputCall } from "./output/fake-output";
import { fakeDocCall } from "./doctools/fake-doctools";
import { fakeSheetsCall } from "./sheets/fake-sheets";
import { fakeWorkspaceCall } from "./workspace/fake-workspace";
import { fakeStandardsCall } from "./standards/fake-standards";

type Raw = { id: string | null; layer?: string; items: any[] };
const PREVIEW = "#DBE0EB";
const IDLE: PromptState = { active: false, message: "Command:", keywords: [], kinds: [], preview: [] };
// eslint-disable-next-line @typescript-eslint/no-unused-vars
const _TYPES: Record<string, string> = { "A-WALL": "Wall", "A-DOOR": "Door", "A-GLAZ": "Window", "A-AREA": "Room", "A-ANNO-DIMS": "Dimension",
  "L-PLNT": "Plant", "C-TOPO": "Topography", LIGHTS: "Light", "A-ELEMENTS": "Element", "0": "Line" };

export class FakeEngine implements Engine {
  readonly kind = "fixtures" as const;
  readonly native = null;
  private listeners: ((n: Notification) => void)[] = [];
  private ready: Promise<void>;
  private hello: any = null;
  private info: any = null;
  private raw: Raw[] = [];
  private decoded: Entry[] = [];
  private selection = new Set<string>();
  private sysvars: Record<string, string> = {};
  private undo: { label: string; raw: string }[] = [];
  private redo: { label: string; raw: string }[] = [];
  private layers: any = null;
  private cmd: null | { name: string; pts: [number, number][]; step: number; cursor: [number, number] } = null;
  private lastCommand = "";
  private nextId = 100000;

  constructor(private base: string) {
    this.ready = this.load();
  }

  private records: { method: string; params: any; result: any; notifications: any[] }[] = [];
  private rec(method: string, pred: (p: any, r: any) => boolean = () => true) { return this.records.find((r) => r.method === method && pred(r.params ?? {}, r.result)); }
  private async fetchJSON(name: string) {
    try { const r = await fetch(`${this.base}/${name}`); if (!r.ok) return null; return await r.json(); } catch { return null; }
  }
  /** Loads build/engine-fixtures (index.json + {request, response, notifications} files or arrays of them). */
  private async load() {
    const index: string[] = (await this.fetchJSON("index.json")) ?? [];
    for (const f of index) {
      if (/^meshes/.test(f)) continue;
      const j = await this.fetchJSON(f);
      for (const x of Array.isArray(j) ? j : j ? [j] : []) if (x?.request?.method && x.response && "result" in x.response) this.records.push({ method: x.request.method, params: x.request.params ?? {}, result: x.response.result, notifications: x.notifications ?? [] });
    }
    this.hello = this.rec("engine.hello")?.result ?? { version: "fixtures", commands: [], sysvars: [] };
    for (const v of Array.isArray(this.hello.sysvars) ? this.hello.sysvars : Object.entries(this.hello.sysvars ?? {}).map(([name, d]) => ({ name, default: d }))) if (v.default !== undefined) this.sysvars[v.name] = String(v.default);
    for (const r of this.records) if (r.method === "sysvar.get" && r.result?.name) this.sysvars[r.result.name] = String(r.result.value);
    Object.assign(this.sysvars, { GRIDMODE: "1", POLARMODE: "1", OTRACK: "1", DYNMODE: "1", LWDISPLAY: "1" });
    this.newDoc("Drawing1");
  }

  onNotify(cb: (n: Notification) => void) { this.listeners.push(cb); }
  private emit(method: string, params: any) { setTimeout(() => this.listeners.forEach((l) => l({ method, params })), 0); }
  private log(text: string) { this.emit("log", { text }); }
  private changed(...what: string[]) { this.emit("changed", { what }); }

  private newDoc(title: string, units = "millimeters") {
    this.raw = []; this.decoded = []; this.selection.clear(); this.undo = []; this.redo = [];
    this.info = { title, path: null, dirty: false, units, unitAbbreviation: units === "inches" ? "in" : "mm", levels: [{ id: 0, name: "Ground Floor", elevation: 0, height: 3000 }],
      currentLevel: "Ground Floor", currentLevelId: 0, layouts: ["Sheet 1"], extents: [0, 0, 10000, 10000], empty: true, entities: 0, elements: 0 };
    this.layers = { current: "0", layers: [{ name: "0", color: "#ffffff", linetype: "Continuous", lineweight: 0.25, visible: true, frozen: false, locked: false, count: 0, current: true }] };
    this.sysvars.CLAYER = "0"; this.sysvars.CLEVEL = "Ground Floor"; this.sysvars.INSUNITS = units;
  }
  private openFixture(path: string) {
    const open = this.rec("doc.open")?.result ?? this.rec("doc.info")?.result;
    const dl = this.rec("view.drawList", (p) => !p.layout && (p.level === undefined || p.level === 0 || p.level === "Ground Floor"))?.result;
    if (!open || !dl) throw { code: -32000, message: `Cannot open ${path}: no recorded drawing in the fixtures.` };
    this.raw = this.group(dl.items ?? []);
    this.decode();
    this.info = JSON.parse(JSON.stringify({ ...open, path: path || open.path }));
    this.layers = JSON.parse(JSON.stringify(this.rec("panel.layers")?.result ?? this.layers));
    this.selection.clear(); this.undo = []; this.redo = [];
    this.sysvars.CLEVEL = this.info.currentLevel ?? "Ground Floor";
    for (const r of this.records) if (r.method === "doc.open") for (const n of r.notifications) if (n.method === "log") this.log(n.params.text);
    if (!this.records.find((r) => r.method === "doc.open")?.notifications.some((n: any) => n.method === "log")) this.log(`Opened ${String(path).split(/[\\/]/).pop()} — ${this.info.entities ?? this.raw.length} objects, ${this.info.elements ?? 0} building elements.`);
  }
  /** Groups a flat engine item list into per-object entries ({id, items}); decoration keeps id null. */
  private group(items: any[]): Raw[] {
    const out: Raw[] = [], by = new Map<string, Raw>();
    for (const it of items) {
      if (it.id === undefined || it.id === null) { out.push({ id: null, items: [it] }); continue; }
      const k = String(it.id);
      let e = by.get(k); if (!e) { e = { id: k, items: [] }; by.set(k, e); out.push(e); }
      e.items.push(it);
    }
    return out;
  }
  private decode() { this.decoded = decodeDrawList({ entries: this.raw }); }
  private snapshot(label: string) { this.undo.push({ label, raw: JSON.stringify(this.raw) }); this.redo = []; this.info.dirty = true; }
  private flat() { return this.raw.flatMap((e) => e.items.map((it: any) => (e.id ? { ...it, id: isNaN(Number(e.id)) ? e.id : Number(e.id) } : it))); }
  private history() { return { undo: this.undo.map((u) => u.label), redo: this.redo.map((u) => u.label), canUndo: this.undo.length > 0, canRedo: this.redo.length > 0, undoLabel: this.undo.at(-1)?.label ?? null, redoLabel: this.redo.at(-1)?.label ?? null, commands: [], dirty: !!this.info.dirty }; }

  async call(method: string, params: any = {}): Promise<any> {
    await this.ready;
    const wsr = fakeWorkspaceCall(this as any, method, params);
    if (wsr !== undefined) return wsr;
    const gsr = fakeStandardsCall(this as any, method, params);
    if (gsr !== undefined) return gsr;
    const outp = fakeOutputCall(this as any, method, params);
    if (outp !== undefined) return outp;
    const dlg = fakeDialogCall(this as any, method, params);
    if (dlg !== undefined) return dlg;
    const doc = fakeDocCall(this as any, method, params);
    if (doc !== undefined) return doc;
    const sh = fakeSheetsCall(this as any, method, params);
    if (sh !== undefined) return sh;
    switch (method) {
      case "engine.hello": return this.hello;
      case "doc.new": {
        const imperial = /imperial/i.test(params.template ?? "");
        this.newDoc("Drawing1", imperial ? "inches" : "millimeters");
        this.log(imperial ? "New drawing (imperial, inches)" : params.template === "building" ? "New building (levels, grid and sheets)" : "New drawing (metric, millimetres)");
        this.changed("document", "selection", "sysvars");
        return this.info;
      }
      case "doc.open": this.openFixture(String(params.path ?? "")); this.changed("document", "selection", "sysvars"); return this.info;
      case "doc.save": this.info.dirty = false; if (params.path) this.info.path = params.path; this.log(`Saved ${this.info.path ?? this.info.title}`); this.changed("document"); return this.info;
      case "doc.info": return this.info;
      case "view.drawList": {
        if (params.layout !== undefined) return this.rec("view.drawList", (p) => p.layout !== undefined)?.result ?? { items: [] };
        const lvl = params.level ?? this.info.currentLevel;
        if (lvl !== undefined && lvl !== 0 && lvl !== "Ground Floor" && this.info.title !== "Drawing1") return this.rec("view.drawList", (p) => p.level !== undefined && p.level !== 0)?.result ?? { items: [] };
        return { items: this.flat(), count: this.raw.length, bounds: this.info.extents, grid: { show: this.sysvars.GRIDMODE === "1", spacing: 100 } };
      }
      case "command.run": return this.run(String(params.line ?? ""));
      case "command.complete": return [];
      case "input.text": return this.text(String(params.text ?? ""));
      case "input.point": {
        const p: [number, number] = [Number(params.x), Number(params.y)];
        if (params.snap !== false && this.cmd) { const c = this.cursor(p, 10 / Number(params.pixelsPerUnit || this.ppu)); if (c.snap) { const q = snapPoint(c.snap); p[0] = q[0]; p[1] = q[1]; } }
        return this.point(p);
      }
      case "input.key": return this.key(String(params.key));
      case "input.cursor": if (params.pixelsPerUnit) this.ppu = Number(params.pixelsPerUnit); return this.cursor([Number(params.x), Number(params.y)], 10 / this.ppu);
      case "pick": {
        const e = pickEntry(this.decoded, [params.x, params.y], params.tolerance ?? 6 / this.ppu);
        if (params.add === false && !params.toggle) this.selection.clear();
        if (e?.id) { if (params.toggle && this.selection.has(e.id)) this.selection.delete(e.id); else this.selection.add(e.id); }
        this.changed("selection");
        return { ...this.selectionResult(), hit: e?.id ? Number(e.id) : null };
      }
      case "select.window": {
        const x0 = Math.min(params.x0, params.x1), x1 = Math.max(params.x0, params.x1), y0 = Math.min(params.y0, params.y1), y1 = Math.max(params.y0, params.y1);
        const crossing = params.crossing ?? params.x1 < params.x0;
        if (params.add === false) this.selection.clear();
        for (const e of this.decoded) {
          if (!e.id) continue;
          const [a, b, c, d] = e.bounds;
          const inside = a >= x0 && c <= x1 && b >= y0 && d <= y1;
          const touch = !(c < x0 || a > x1 || d < y0 || b > y1);
          if (crossing ? touch : inside) { if (params.remove) this.selection.delete(e.id); else this.selection.add(e.id); }
        }
        this.changed("selection"); return this.selectionResult();
      }
      case "select.set": this.selection = new Set((params.ids ?? []).map(String)); this.changed("selection"); return this.selectionResult();
      case "select.get": return this.selectionResult();
      case "grips.get": return this.grips();
      case "grips.drag": { const g = this.dragGrip(params); return { changed: [params.id], grips: g }; }
      case "edit.undo": case "edit.redo": {
        if (this.cmd) this.finish();
        const from = method === "edit.undo" ? this.undo : this.redo, to = method === "edit.undo" ? this.redo : this.undo;
        const s = from.pop();
        if (!s) { this.log(method === "edit.undo" ? "Nothing to undo." : "Nothing to redo."); return this.history(); }
        to.push({ label: s.label, raw: JSON.stringify(this.raw) });
        this.raw = JSON.parse(s.raw); this.decode(); this.selection.clear();
        this.log(`${method === "edit.undo" ? "Undo" : "Redo"} ${s.label}`);
        this.changed("document", "selection"); return this.history();
      }
      case "sysvar.get": { const n = String(params.name).toUpperCase(); return { name: n, value: this.sysvars[n] ?? null }; }
      case "sysvar.set": return this.setVar(String(params.name), String(params.value));
      case "panel.properties": return this.properties();
      case "panel.layers": return this.layers;
      case "panel.levels": return { current: this.info.currentLevel, units: this.info.unitAbbreviation, levels: [...this.info.levels].sort((a: any, b: any) => b.elevation - a.elevation).map((l: any) => ({ ...l, current: l.name === this.info.currentLevel })) };
      case "panel.history": return this.history();
      case "panel.materials": return this.rec("panel.materials")?.result ?? { materials: [] };
      case "panel.sheets": return this.rec("panel.sheets")?.result ?? { current: "Model", sheets: this.info.layouts.map((name: string, index: number) => ({ index, name, paper: { name: "A3", width: 420, height: 297 } })) };
      case "panel.set": return this.panelSet(params);
      case "file.export": this.log(`Exported ${params.path ?? ""}`); return { path: params.path, format: params.format, bytes: 0 };
      case "file.import": this.log(`Import needs archi-engine (fixture mode): ${params.path}`); return { summary: "nothing imported", entityIds: [], elementIds: [] };
      case "render.settings": case "render.preset": return this.rec(method)?.result ?? { preset: params.name ?? "Daylight" };
      case "model.meshes": {
        // The recorded Cedar House meshes (meshes-level-0.json: Ground Floor, full detail) when that drawing is open.
        const rec = this.info.empty ? null : await this.fetchJSON("meshes-level-0.json");
        return rec?.response?.result ?? { meshes: [], lights: [], sun: { azimuth: 228, altitude: 11 } };
      }
      case "engine.log": return { lines: [] };
      // 3D view (view3d.info / sectionCaps / transform replay the recording): camera reports and image writes.
      case "view3d.setCamera": return { ok: true };
      case "view3d.saveImage": this.log(`Image saved (fixture mode, not written): ${params.path ?? ""}`); return { path: params.path, bytes: 0 };
    }
    const r = this.rec(method);
    if (r) return JSON.parse(JSON.stringify(r.result));
    throw { code: -32601, message: `Method not found: ${method}` };
  }
  private ppu = 0.05;

  private selectionResult() {
    const ids = [...this.selection];
    const n = ids.length;
    return { ids: ids.map((i) => (isNaN(Number(i)) ? i : Number(i))), summary: n ? `${n} object${n === 1 ? "" : "s"}` : "No selection", types: [] };
  }
  private properties() {
    if (this.selection.size === 0) {
      const r = this.rec("panel.properties", (_p, res) => !(res?.ids ?? []).length)?.result;
      const base = r ? JSON.parse(JSON.stringify(r)) : { ids: [], summary: "No selection", types: [], project: { name: this.info.title, number: "", client: "", address: "", author: "" }, drawing: {}, rows: [] };
      base.drawing = { ...base.drawing, units: this.info.units, currentLayer: this.sysvars.CLAYER ?? "0", currentLevel: this.info.currentLevel, layers: this.layers.layers.length };
      if (this.info.title === "Drawing1") base.drawing = { units: this.info.units, currentLayer: this.sysvars.CLAYER ?? "0", currentLevel: this.info.currentLevel, objects: this.raw.length, elements: 0, layers: this.layers.layers.length, blocks: 0, file: "—" };
      return base;
    }
    const ids = [...this.selection];
    const wall = this.rec("panel.properties", (_p, res) => (res?.ids ?? []).length === 1)?.result;
    if (wall && ids.length === 1 && String(wall.ids[0]) === ids[0]) return wall;
    const e = ids.length === 1 ? this.decoded.find((d) => d.id === ids[0]) : null;
    const rows = [{ name: "type", value: ids.length === 1 ? "object" : "*VARIES*", readOnly: true }, { name: "layer", value: "0", readOnly: false }, { name: "color", value: "ByLayer", readOnly: false },
      { name: "linetype", value: "ByLayer", readOnly: false }, { name: "lineweight", value: "ByLayer", readOnly: false }];
    if (e) rows.push({ name: "minX", value: e.bounds[0].toFixed(2), readOnly: true }, { name: "minY", value: e.bounds[1].toFixed(2), readOnly: true }, { name: "width", value: (e.bounds[2] - e.bounds[0]).toFixed(2), readOnly: true }, { name: "height", value: (e.bounds[3] - e.bounds[1]).toFixed(2), readOnly: true });
    if (ids.length === 1) rows.unshift({ name: "id", value: ids[0], readOnly: true });
    return { ...this.selectionResult(), rows };
  }
  private panelSet(p: any) {
    const key = String(p.key);
    if (p.panel === "layers") {
      if (key === "current") { this.layers.current = p.value; this.sysvars.CLAYER = p.value; this.layers.layers.forEach((l: any) => (l.current = l.name === p.value)); }
      else {
        const dot = key.lastIndexOf("."), name = key.slice(0, dot), prop = key.slice(dot + 1);
        const l = this.layers.layers.find((x: any) => x.name === name);
        if (l) l[prop] = typeof l[prop] === "boolean" ? p.value === true || p.value === "1" || p.value === "true" : p.value;
      }
      this.changed("document"); return this.layers;
    }
    if (p.panel === "levels" && key === "current") { this.info.currentLevel = p.value; this.sysvars.CLEVEL = p.value; this.changed("document"); return this.call("panel.levels"); }
    if (p.panel === "properties") {
      if (key === "project.name") this.info.title = p.value;
      this.info.dirty = true; this.changed("document"); return this.properties();
    }
    if (p.panel === "sheets" && key === "current") { this.changed("document"); return this.call("panel.sheets"); }
    return { ok: true };
  }
  private setVar(name: string, value: string) {
    const n = name.toUpperCase();
    this.sysvars[n] = value;
    if (n === "CLAYER") this.layers.current = value;
    if (n === "CLEVEL") this.info.currentLevel = value;
    this.changed("sysvars");
    return { name: n, value };
  }

  private grips() {
    const out: any[] = [];
    if (this.selection.size > 300) return out;
    for (const e of this.decoded) {
      if (!e.id || !this.selection.has(e.id)) continue;
      const seen = new Set<string>();
      let i = 0;
      for (const it of e.items) {
        const pts = it.type === "stroke" ? it.points : it.type === "text" ? [it.position] : [];
        for (const p of pts) { const k = p.join(","); if (seen.has(k)) continue; seen.add(k); out.push({ id: isNaN(Number(e.id)) ? e.id : Number(e.id), index: i++, x: p[0], y: p[1], kind: "vertex" }); }
      }
    }
    return out.slice(0, 2000);
  }
  private dragGrip(p: any) {
    const g = this.grips().find((x) => String(x.id) === String(p.id) && x.index === p.index);
    const r = this.raw.find((x) => x.id === String(p.id));
    if (!g || !r) return this.grips();
    this.snapshot("Grip Edit");
    const move = (pt: any) => { if (Array.isArray(pt) && Math.abs(pt[0] - g.x) < 1e-6 && Math.abs(pt[1] - g.y) < 1e-6) { pt[0] = p.x; pt[1] = p.y; } };
    for (const it of r.items) { (it.points ?? []).forEach(move); (it.loops ?? []).forEach((l: any[]) => l.forEach(move)); if (it.text) move(it.text.position); }
    this.decode(); this.changed("document"); return this.grips();
  }

  // ---- minimal command simulation ----
  private resolve(name: string): string | null {
    const n = name.toUpperCase();
    for (const c of this.hello.commands ?? []) if (c.name === n || (c.aliases ?? []).includes(n)) return c.name;
    const builtin: Record<string, string> = { L: "LINE", C: "CIRCLE", REC: "RECTANG", RECTANGLE: "RECTANG", E: "ERASE", PL: "PLINE", Z: "ZOOM", U: "UNDO" };
    return builtin[n] ?? (["LINE", "CIRCLE", "RECTANG", "ERASE", "PLINE", "ZOOM", "UNDO", "REDO"].includes(n) ? n : null);
  }
  private prompt(): PromptState {
    const c = this.cmd;
    if (!c) return IDLE;
    const base = c.pts.length ? c.pts[c.pts.length - 1] : null;
    let message = "", keywords: string[] = [], preview: any[] = [], defaultValue: string | undefined;
    const cur = c.cursor;
    const st = { color: PREVIEW, lineweight: 0.25, dash: [] };
    if (c.name === "LINE" || c.name === "PLINE") {
      message = c.pts.length === 0 ? "Specify first point" : "Specify next point";
      keywords = c.pts.length >= 2 ? ["Close", "Undo"] : c.pts.length ? ["Undo"] : [];
      if (base) preview = [{ type: "stroke", points: [base, cur], closed: false, style: st }];
    } else if (c.name === "CIRCLE") {
      message = c.pts.length === 0 ? "Specify center point for circle" : "Specify radius of circle";
      keywords = c.pts.length === 0 ? ["3P", "2P", "Ttr"] : ["Diameter"];
      if (base) { const r = Math.hypot(cur[0] - base[0], cur[1] - base[1]); preview = [{ type: "stroke", points: circle(base, r), closed: true, style: st }]; defaultValue = undefined; }
    } else if (c.name === "RECTANG") {
      message = c.pts.length === 0 ? "Specify first corner point" : "Specify other corner point";
      keywords = c.pts.length === 0 ? ["Chamfer", "Elevation", "Fillet", "Width"] : ["Area", "Dimensions", "Rotation"];
      if (base) preview = [{ type: "stroke", points: [base, [cur[0], base[1]], cur, [base[0], cur[1]]], closed: true, style: st }];
    } else if (c.name === "ERASE") { message = "Select objects"; }
    const full = message + (keywords.length ? ` [${keywords.join("/")}]` : "") + ":";
    return { active: true, command: c.name, message: full, label: message, keywords, kinds: c.name === "ERASE" ? ["selection"] : keywords.length ? ["point", "keyword"] : ["point"], defaultValue, preview, base: c.name === "ERASE" ? null : base } as any;
    function circle(o: [number, number], r: number) { const p: [number, number][] = []; for (let i = 0; i < 72; i++) p.push([o[0] + r * Math.cos((i / 72) * 2 * Math.PI), o[1] + r * Math.sin((i / 72) * 2 * Math.PI)]); return p; }
  }
  private add(label: string, items: any[]) {
    this.snapshot(label);
    this.raw.push({ id: String(this.nextId++), layer: this.sysvars.CLAYER ?? "0", items });
    this.decode(); this.changed("document");
  }
  private finish(): PromptState { this.cmd = null; this.emit("prompt", IDLE); return IDLE; }
  private run(line: string): PromptState {
    const toks = line.trim().split(/\s+/).filter(Boolean);
    if (!toks.length) { if (this.lastCommand) return this.run(this.lastCommand); return IDLE; }
    if (this.cmd) this.finish();
    const name = this.resolve(toks[0]);
    this.log(`Command: ${toks[0].toUpperCase()}`);
    if (!name) {
      if (/^[A-Z_]+$/i.test(toks[0]) && toks[0].toUpperCase() in this.sysvars) {
        if (toks[1] !== undefined) { this.setVar(toks[0], toks[1]); } else this.log(`${toks[0].toUpperCase()} = ${this.sysvars[toks[0].toUpperCase()]}`);
        return IDLE;
      }
      this.log(`Unknown command "${toks[0].toUpperCase()}". Press F1 for help.`); return IDLE;
    }
    this.lastCommand = toks[0];
    if (name === "UNDO") { this.call("edit.undo"); return IDLE; }
    if (name === "REDO") { this.call("edit.redo"); return IDLE; }
    if (name === "ZOOM") { this.emit("view", { zoom: "extents" }); return IDLE; }
    if (name === "ERASE" && this.selection.size) {
      this.snapshot("Erase"); const n = this.selection.size;
      this.raw = this.raw.filter((r) => !r.id || !this.selection.has(r.id)); this.selection.clear(); this.decode();
      this.log(`${n} object${n === 1 ? "" : "s"} erased.`); this.changed("document", "selection"); return IDLE;
    }
    if (!["LINE", "PLINE", "CIRCLE", "RECTANG", "ERASE"].includes(name)) {
      this.log(`${name} runs in archi-engine; the fixture engine only simulates LINE, PLINE, CIRCLE, RECTANG and ERASE.`);
      return IDLE;
    }
    this.cmd = { name, pts: [], step: 0, cursor: [0, 0] };
    let st = this.prompt();
    for (const t of toks.slice(1)) st = this.text(t);
    this.emit("prompt", st);
    return st;
  }
  private point(p: [number, number]): PromptState {
    const c = this.cmd;
    if (!c) return IDLE;
    c.cursor = p;
    const st = { color: "#FFFFFF", lineweight: 0.25, dash: [] };
    if (c.name === "LINE" || c.name === "PLINE") {
      if (c.pts.length) this.add("Line", [{ type: "stroke", points: [c.pts[c.pts.length - 1], p], closed: false, style: st }]);
      c.pts.push(p);
    } else if (c.name === "CIRCLE") {
      if (!c.pts.length) c.pts.push(p);
      else { const o = c.pts[0], r = Math.hypot(p[0] - o[0], p[1] - o[1]); const pts: any[] = []; for (let i = 0; i < 96; i++) pts.push([o[0] + r * Math.cos((i / 96) * 2 * Math.PI), o[1] + r * Math.sin((i / 96) * 2 * Math.PI)]); this.add("Circle", [{ type: "stroke", points: pts, closed: true, style: st }]); return this.finish(); }
    } else if (c.name === "RECTANG") {
      if (!c.pts.length) c.pts.push(p);
      else { const b = c.pts[0]; this.add("Rectangle", [{ type: "stroke", points: [b, [p[0], b[1]], p, [b[0], p[1]]], closed: true, style: st }]); return this.finish(); }
    }
    const s = this.prompt(); this.emit("prompt", s); return s;
  }
  private text(t: string): PromptState {
    const c = this.cmd;
    if (!c) return t.trim() ? this.run(t) : this.run("");
    const s = t.trim();
    if (!s) return this.key("Enter");
    const kw = this.prompt().keywords.find((k) => k.toUpperCase().startsWith(s.toUpperCase()));
    if (kw === "Close" && c.pts.length >= 2) { this.point(c.pts[0]); return this.finish(); }
    if (kw === "Undo" && c.pts.length) { c.pts.pop(); if (this.undo.length && c.pts.length) this.call("edit.undo"); const st = this.prompt(); this.emit("prompt", st); return st; }
    if (kw) { this.log(`${kw} is simulated only in archi-engine.`); return this.prompt(); }
    const base = c.pts.length ? c.pts[c.pts.length - 1] : [0, 0];
    let m = s.match(/^(@)?(-?[\d.]+)\s*[,;]\s*(-?[\d.]+)$/);
    if (m) return this.point(m[1] ? [base[0] + Number(m[2]), base[1] + Number(m[3])] : [Number(m[2]), Number(m[3])]);
    m = s.match(/^@?(-?[\d.]+)\s*<\s*(-?[\d.]+)$/);
    if (m) { const a = (Number(m[2]) * Math.PI) / 180; return this.point([base[0] + Number(m[1]) * Math.cos(a), base[1] + Number(m[1]) * Math.sin(a)]); }
    if (/^-?[\d.]+$/.test(s) && c.pts.length) {
      const d = Number(s), dx = c.cursor[0] - base[0], dy = c.cursor[1] - base[1], l = Math.hypot(dx, dy) || 1;
      if (c.name === "CIRCLE") return this.point([base[0] + d, base[1]]);
      return this.point([base[0] + (dx / l) * d, base[1] + (dy / l) * d]);
    }
    this.log("Invalid point or option keyword.");
    return this.prompt();
  }
  private key(k: string): PromptState {
    if (k === "Escape") { if (this.cmd) { this.log("*Cancel*"); return this.finish(); } return IDLE; }
    if (k === "Enter" || k === "Space") { if (this.cmd) return this.finish(); return this.run(""); }
    return this.prompt();
  }
  private cursor(p: [number, number], tol: number): PromptState {
    let snap: any = null;
    const osOn = !((Number(this.sysvars.OSMODE ?? 0) & 16384) || Number(this.sysvars.OSMODE ?? 0) === 0);
    if (osOn && tol > 0 && this.cmd) {
      let best = tol;
      for (const e of this.decoded) {
        const b = e.bounds;
        if (p[0] < b[0] - tol || p[0] > b[2] + tol || p[1] < b[1] - tol || p[1] > b[3] + tol) continue;
        for (const it of e.items) if (it.type === "stroke") {
          const pts = it.points;
          for (let i = 0; i < pts.length; i++) {
            const d = Math.hypot(pts[i][0] - p[0], pts[i][1] - p[1]);
            if (d < best) { best = d; snap = { kind: "endpoint", point: pts[i] }; }
            if (i + 1 < pts.length) { const m: [number, number] = [(pts[i][0] + pts[i + 1][0]) / 2, (pts[i][1] + pts[i + 1][1]) / 2]; const dm = Math.hypot(m[0] - p[0], m[1] - p[1]); if (dm < best) { best = dm; snap = { kind: "midpoint", point: m }; } }
          }
        }
      }
    }
    const cursor: [number, number] = snap ? [snap.point[0], snap.point[1]] : p;
    if (this.cmd) this.cmd.cursor = cursor;
    return { ...this.prompt(), cursor, snap, hover: null } as any;
  }
}
