// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Window model (the Windows counterpart of AppModel.swift): engine session, document info, prompt, selection,
// system variables and UI state shared by the ribbon, panels, canvas, command line and status bar.
import type { DocInfo, Hello, PromptState, Selection, CommandInfo } from "../shared/protocol";
import type { Engine } from "./engine";

export type Mode = "2D" | "3D" | "Split" | "Sheet";
export const MODES: Mode[] = ["2D", "3D", "Split", "Sheet"];
export type Evt = "doc" | "prompt" | "log" | "selection" | "sysvars" | "layers" | "drawing" | "ui" | "live" | "panel" | "history" | "start";

const IDLE: PromptState = { active: false, message: "Command:", keywords: [], kinds: [], preview: [] };
function store<T>(key: string, def: T): T { try { const v = localStorage.getItem("archi." + key); return v === null ? def : JSON.parse(v); } catch { return def; } }
function save(key: string, v: unknown) { try { localStorage.setItem("archi." + key, JSON.stringify(v)); } catch {} }

export const TOGGLES: { title: string; key: string; varName: string }[] = [
  { title: "GRID", key: "F7", varName: "GRIDMODE" }, { title: "SNAP", key: "F9", varName: "SNAPMODE" }, { title: "ORTHO", key: "F8", varName: "ORTHOMODE" },
  { title: "POLAR", key: "F10", varName: "POLARMODE" }, { title: "OTRACK", key: "F11", varName: "OTRACK" }, { title: "OSNAP", key: "F3", varName: "OSMODE" },
  { title: "DYN", key: "F12", varName: "DYNMODE" }, { title: "LWT", key: "", varName: "LWDISPLAY" },
];

export class App {
  hello: Hello = { version: "", commands: [], sysvars: {} };
  info: DocInfo | null = null;
  prompt: PromptState = IDLE;
  log: string[] = [];
  inputHistory: string[] = [];
  selection: Selection = { ids: [], summary: "" };
  sysvars: Record<string, string> = {};
  layers: { current: string; layers: any[] } = { current: "0", layers: [] };
  mode: Mode = store("mode", "2D") as Mode;
  panelTab: string = store("panelTab", "Properties");
  showPanels: boolean = store("showPanels", true);
  panelWidth: number = store("panelWidth", 300);
  ribbonTab: string = store("ribbonTab", "Home");
  ribbonCollapsed: boolean = store("ribbonCollapsed", false);
  cleanScreen = false;
  showStart = false;
  showScriptConsole = false;
  activeLayout = 0; // 0 = Model, i = layouts[i-1]
  live = { x: 0, y: 0, zoomPercent: 0, snapHint: "" as string };
  engineError = "";
  commandInput = "";
  private listeners = new Map<Evt, Set<() => void>>();
  private commandIndex = new Map<string, CommandInfo>();
  /** Hooks set by the dialogs (dialogs/index.ts): host notifications, "@ui:" targets, new-drawing preferences. */
  uiHooks: { host?(p: any): boolean; ui?(ref: string): boolean; newTemplate?(t: string): string; afterNew?(t: string): Promise<void> | void } = {};
  /** Hooks set by the canvas. */
  canvas: { zoomExtents(): void; zoomBy(f: number): void; zoomWindow(): void; focus(): void; refresh(): void } | null = null;

  constructor(readonly engine: Engine) {
    engine.onNotify((n) => this.onNotification(n.method, n.params));
  }

  on(evt: Evt | Evt[], cb: () => void) { for (const e of Array.isArray(evt) ? evt : [evt]) { if (!this.listeners.has(e)) this.listeners.set(e, new Set()); this.listeners.get(e)!.add(cb); } }
  emit(...evts: Evt[]) { const done = new Set<() => void>(); for (const e of evts) this.listeners.get(e)?.forEach((cb) => { if (!done.has(cb)) { done.add(cb); cb(); } }); }

  setUI<K extends "mode" | "panelTab" | "showPanels" | "panelWidth" | "ribbonTab" | "ribbonCollapsed">(k: K, v: App[K]) {
    (this as any)[k] = v; save(k, v); this.emit("ui");
  }

  async call(method: string, params: unknown = {}): Promise<any> {
    try { return await this.engine.call(method, params); }
    catch (e: any) { this.print(e?.message ? `Error: ${e.message}` : `Error: ${String(e)}`); throw e; }
  }
  async tryCall(method: string, params: unknown = {}): Promise<any> { try { return await this.engine.call(method, params); } catch { return null; } }

  print(line: string) { for (const l of String(line).split("\n")) this.log.push(l); if (this.log.length > 2000) this.log.splice(0, this.log.length - 2000); this.emit("log"); }

  async init() {
    try {
      this.hello = await this.engine.call("engine.hello", {});
    } catch (e: any) {
      this.engineError = e?.message ?? String(e);
      this.print(`archi-engine is not running: ${this.engineError}`);
    }
    for (const c of this.hello.commands ?? []) { this.commandIndex.set(c.name.toUpperCase(), c); for (const a of c.aliases ?? []) if (!this.commandIndex.has(a.toUpperCase())) this.commandIndex.set(a.toUpperCase(), c); }
    const sv: any = this.hello.sysvars ?? [];
    if (Array.isArray(sv)) { for (const v of sv) if (v?.name && v.default !== undefined) this.sysvars[String(v.name).toUpperCase()] = String(v.default); }
    else for (const [k, v] of Object.entries(sv)) this.sysvars[k.toUpperCase()] = String(v);
    await this.refreshVars();
    await this.refresh(["document", "layers", "selection"]);
  }

  lookup(name: string): CommandInfo | undefined { return this.commandIndex.get(name.toUpperCase()); }
  has(name: string) { return this.commandIndex.size === 0 || this.commandIndex.has(name.toUpperCase()); }
  /** Registered names starting with the typed text (names and aliases), like CommandRegistry.complete. */
  complete(prefix: string, limit = 9): { name: string; command: CommandInfo }[] {
    const p = prefix.toUpperCase();
    const out: { name: string; command: CommandInfo }[] = [];
    const exact = this.commandIndex.get(p);
    if (exact) out.push({ name: p, command: exact });
    const names = [...this.commandIndex.keys()].filter((n) => n.startsWith(p) && n !== p).sort((a, b) => a.length - b.length || a.localeCompare(b));
    for (const n of names) { if (out.length >= limit) break; out.push({ name: n, command: this.commandIndex.get(n)! }); }
    return out;
  }

  get windowTitle() { return `${this.info?.title ?? "Untitled"}${this.info?.dirty ? " •" : ""} — Oanarina Archi Tool`; }
  get isIdle() { return !this.prompt.active; }
  sysvarOn(name: string) {
    const v = this.sysvars[name];
    if (name === "OSMODE") { const n = Number(v ?? 0); return n !== 0 && (n & 16384) === 0; }
    return v === "1" || v === "true" || v === "on";
  }

  async refresh(what: string[]) {
    what = [...what];
    const all = what.includes("all");
    const jobs: Promise<void>[] = [];
    if (what.includes("document")) what = [...what, "layers", "drawing", "properties", "history"];
    if (all || what.includes("document") || what.includes("levels")) jobs.push(this.tryCall("doc.info").then((i) => { if (i) { this.info = i; this.emit("doc"); } }));
    if (all || what.includes("layers")) jobs.push(this.tryCall("panel.layers").then((l) => { if (l) { this.layers = { current: l.current ?? this.sysvars.CLAYER ?? "0", layers: l.layers ?? l.items ?? [] }; this.emit("layers"); } }));
    if (all || what.includes("selection")) jobs.push(this.tryCall("select.get").then((s) => { if (s) { this.selection = { ids: (s.ids ?? []).map(String), summary: s.summary ?? "" }; this.emit("selection"); } }));
    if (all || what.includes("sysvars")) jobs.push(this.refreshVars());
    await Promise.all(jobs);
    if (all || what.includes("drawing") || what.includes("document")) this.emit("drawing");
    if (all || what.some((w) => ["properties", "history", "document", "selection", "layers", "levels", "drawing"].includes(w))) this.emit("panel");
  }
  async refreshVars() {
    const names = [...TOGGLES.map((t) => t.varName), "CLAYER", "CLEVEL", "INSUNITS", "CECOLOR", "CELTYPE", "CELWEIGHT", "DIMSTYLE", "TEXTSIZE", "CANNOSCALE", "GRIDUNIT"];
    await Promise.all(names.map((n) => this.tryCall("sysvar.get", { name: n }).then((r) => { if (r && r.value !== undefined && r.value !== null) this.sysvars[n] = String(r.value); })));
    this.emit("sysvars");
  }

  private onNotification(method: string, params: any) {
    switch (method) {
      case "log": if (params?.text && !params.stderr) this.print(params.text); break;
      case "prompt": this.setPrompt(params); break;
      case "changed": this.refresh(params?.what ?? ["all"]); break;
      case "view": if (params?.zoom === "extents") this.canvas?.zoomExtents(); break;
      case "host": this.host(params ?? {}); break;
      case "ready": break;
      case "engineExit": this.engineError = params?.message ?? "stopped"; this.print(`The engine stopped: ${this.engineError}`); break;
    }
  }
  /** `host` notifications: a command asks the UI for a dialog, a zoom, a view mode or a panel (docs/ENGINE-PROTOCOL.md). */
  private async host(p: any) {
    if (this.uiHooks.host?.(p)) return;
    switch (p.action) {
      case "open": return this.open();
      case "saveAs": return this.save(true);
      case "export": return this.exportAs(String(p.format ?? "pdf"));
      case "import": { const f = await this.engine.native?.openFileDialog({ title: "Import" }); if (f) { await this.tryCallLogged("file.import", { path: f }); await this.refresh(["document"]); } return; }
      case "plot": window.print(); return;
      case "zoomExtents": return this.canvas?.zoomExtents();
      case "zoomWindow": if (Array.isArray(p.rect)) this.hostView?.zoomTo(p.rect); return;
      case "zoomScale": if (p.scale) this.canvas?.zoomBy(Number(p.scale)); return;
      case "pan": if (Array.isArray(p.delta)) this.hostView?.pan(p.delta); return;
      case "regen": return this.emit("drawing");
      case "show2D": return this.setUI("mode", "2D");
      case "show3D": case "render": case "walkthrough": this.setUI("mode", "3D"); break;
      case "showSplit": return this.setUI("mode", "Split");
      case "showPanel": if (p.panel) { this.showPanels = true; save("showPanels", true); this.setUI("panelTab", String(p.panel)); } return;
    }
    // setViewStyle, setView, render, walkthrough: for the 3D view module.
    document.dispatchEvent(new CustomEvent("archi:host", { detail: p }));
  }
  hostView: { zoomTo(r: [number, number, number, number]): void; pan(d: [number, number]): void } | null = null;

  setPrompt(p: PromptState | null | undefined) {
    if (!p || typeof p !== "object") return;
    this.prompt = { ...IDLE, ...p, keywords: p.keywords ?? [], kinds: p.kinds ?? [], preview: p.preview ?? [] };
    this.emit("prompt");
  }

  // ---- commands ----
  async runCommand(line: string) {
    if (!line.trim()) return;
    this.showStart && this.closeStart();
    if (line.startsWith("@")) return this.action(line);
    const st = await this.tryCallLogged("command.run", { line });
    if (st) this.setPrompt(st);
    this.canvas?.focus();
  }
  private async tryCallLogged(method: string, params: unknown) {
    try { return await this.engine.call(method, params); }
    catch (e: any) { this.print(`${e?.message ?? e}`); return null; }
  }
  /** Enter/Space in the command line: feeds the active prompt or starts a command (empty = repeat the last). */
  async submitLine(text: string) {
    const t = text.trim();
    if (t) { this.inputHistory = this.inputHistory.filter((x) => x !== t); this.inputHistory.push(t); if (this.inputHistory.length > 100) this.inputHistory.shift(); }
    if (this.prompt.active) {
      const st = await this.tryCallLogged(t ? "input.text" : "input.key", t ? { text: t } : { key: "Enter" });
      if (st) this.setPrompt(st);
    } else if (t) await this.runCommand(t);
    else { const st = await this.tryCallLogged("input.key", { key: "Enter" }); if (st) this.setPrompt(st); }
  }
  async keyword(k: string) { const st = await this.tryCallLogged("input.text", { text: k }); if (st) this.setPrompt(st); this.canvas?.focus(); }
  async cancel() {
    if (this.prompt.active) { const st = await this.tryCallLogged("input.key", { key: "Escape" }); if (st) this.setPrompt(st); }
    else if (this.selection.ids.length) await this.tryCall("select.set", { ids: [] }).then(() => this.refresh(["selection"]));
  }
  async toggleVar(name: string, title?: string) {
    const on = this.sysvarOn(name);
    let value: string;
    if (name === "OSMODE") { const n = Number(this.sysvars.OSMODE ?? 4133) || 4133; value = String(on ? n | 16384 : n & ~16384); }
    else value = on ? "0" : "1";
    const r = await this.tryCallLogged("sysvar.set", { name, value });
    if (r !== null) { this.sysvars[name] = value; this.print(`<${(title ?? name)[0]}${(title ?? name).slice(1).toLowerCase()} ${on ? "off" : "on"}>`); this.emit("sysvars"); this.canvas?.refresh(); }
  }
  async setVar(name: string, value: string) { const r = await this.tryCallLogged("sysvar.set", { name, value }); if (r !== null) { this.sysvars[name] = value; this.emit("sysvars"); await this.refresh(["layers", "document", "properties"]); } }
  async undo() { const st = await this.tryCallLogged("edit.undo", {}); if (st && typeof st === "object" && "active" in st) this.setPrompt(st); await this.refresh(["drawing", "selection", "history"]); }
  async redo() { const st = await this.tryCallLogged("edit.redo", {}); if (st && typeof st === "object" && "active" in st) this.setPrompt(st); await this.refresh(["drawing", "selection", "history"]); }
  async selectAll() { const e = this.info?.extents ?? [-1e9, -1e9, 1e9, 1e9]; await this.tryCall("select.window", { x0: -1e12, y0: -1e12, x1: 1e12, y1: 1e12, crossing: true }); void e; await this.refresh(["selection"]); }

  // ---- files ----
  closeStart() { this.showStart = false; this.emit("start"); }
  async newDocument(template = "metric") {
    const kind = this.uiHooks.newTemplate?.(template) ?? template;
    const i = await this.tryCallLogged("doc.new", { template: kind });
    if (i) { this.info = i; await this.uiHooks.afterNew?.(template); }
    this.mode = "2D"; this.closeStart();
    await this.refresh(["all"]);
    this.canvas?.zoomExtents();
  }
  async open(path?: string | null) {
    const n = this.engine.native;
    if (!path) {
      if (!n) { this.print("Open needs the Windows app (file dialog)."); return; }
      path = await n.openFileDialog({ title: "Open", filters: [{ name: "Drawings", extensions: ["archi", "dxf", "dwg", "ifc"] }, { name: "All files", extensions: ["*"] }] });
      if (!path) return;
    }
    const i = await this.tryCallLogged("doc.open", { path });
    if (!i) return;
    this.info = i; this.closeStart();
    await n?.addRecent(path);
    await this.refresh(["all"]);
    this.canvas?.zoomExtents();
  }
  async openSample(name: string) {
    const p = (await this.engine.native?.samplePath(name)) ?? `Samples/${name}.archi`;
    if (!p) { await this.newDocument("metric"); return this.buildSampleHouse(); }
    await this.open(p);
  }
  /** Same command script as StartView.buildSampleHouse on the Mac. */
  async buildSampleHouse() {
    await this.newDocument("metric");
    this.print("Building the sample house…");
    const script = ["OSMODE 0", "WALL 0,0 12000,0 12000,8000 0,8000 C", "WALL 5000,0 5000,8000", "WALL 5000,4500 12000,4500",
      "DOOR 2500,0", "DOOR 5000,6000", "DOOR 8000,4500", "WINDOW 0,4000", "WINDOW 8500,0", "WINDOW 2500,8000", "WINDOW 9000,8000", "WINDOW 12000,2200", "WINDOW 12000,6200",
      "SLAB -150,-150 12150,-150 12150,8150 -150,8150 C", "ROOF -150,-150 12150,-150 12150,8150 -150,8150 C",
      "ROOM Name Living 2500,4000 Name Bedroom 8500,6250 Name Kitchen 8500,2250",
      "COMPONENT Bed 8500,6600", "COMPONENT Sofa 2500,6200", "COMPONENT Table 2500,3000", "COMPONENT Kitchen 8500,600",
      "DIMLINEAR 0,0 12000,0 6000,-1500", "DIMLINEAR 12000,0 12000,8000 13500,4000", "OSMODE 4133"];
    for (const l of script) { const st = await this.tryCallLogged("command.run", { line: l }); if (st?.active) await this.tryCall("input.key", { key: "Escape" }); }
    this.print("Sample house ready. Switch to 3D (View ▸ 3D) to explore it.");
    await this.refresh(["all"]);
    this.canvas?.zoomExtents();
  }
  async save(as = false) {
    const n = this.engine.native;
    let path = this.info?.path ?? null;
    if (as || !path) {
      if (!n) { await this.tryCallLogged("doc.save", {}); return; }
      path = await n.saveFileDialog({ title: as ? "Save As" : "Save", defaultPath: (this.info?.title ?? "Untitled") + ".archi", filters: [{ name: "Archi project", extensions: ["archi"] }, { name: "DXF", extensions: ["dxf"] }] });
      if (!path) return;
    }
    const i = await this.tryCallLogged("doc.save", { path });
    if (i) { this.info = { ...(this.info as DocInfo), ...i }; await n?.addRecent(path!); this.emit("doc"); }
  }
  async exportAs(format: string) {
    const n = this.engine.native;
    const ext = format.split(":")[0];
    const path = n ? await n.saveFileDialog({ title: `Export ${ext.toUpperCase()}`, defaultPath: `${this.info?.title ?? "Untitled"}.${ext}`, filters: [{ name: ext.toUpperCase(), extensions: [ext] }] }) : `${this.info?.title ?? "Untitled"}.${ext}`;
    if (path) await this.tryCallLogged("file.export", { format, path });
  }

  /** Shell actions ("@…") used by ribbon buttons that open panels or change the view instead of running a command. */
  async action(a: string) {
    const [k, v] = [a.slice(1).split(":")[0], a.slice(a.indexOf(":") + 1)];
    switch (k) {
      case "panel": this.showPanels = true; save("showPanels", true); this.setUI("panelTab", v); this.emit("panel"); break;
      case "mode": this.setUI("mode", v as Mode); break;
      case "zoom": if (v === "extents") this.canvas?.zoomExtents(); else if (v === "in") this.canvas?.zoomBy(1.5); else if (v === "out") this.canvas?.zoomBy(1 / 1.5); else if (v === "window") this.canvas?.zoomWindow(); break;
      case "selectAll": await this.selectAll(); break;
      case "cleanScreen": this.cleanScreen = !this.cleanScreen; this.emit("ui"); break;
      case "export": await this.exportAs(v); break;
      case "scriptConsole": this.showScriptConsole = !this.showScriptConsole; this.emit("ui"); break;
      case "runScript": {
        const p = await this.engine.native?.openFileDialog({ title: "Run Script", filters: [{ name: "Scripts", extensions: ["js", "scr", "txt"] }] });
        if (p) await this.runCommand(`SCRIPT "${p}"`);
        break;
      }
      case "agent": await this.runCommand("AGENTSERVER"); break;
      case "newWindow": {
        const req = v === "sample" ? { kind: "sample" } : v === "blankMetric" ? { kind: "new", path: "metric" } : v === "blankImperial" ? { kind: "new", path: "imperial" } : v === "building" ? { kind: "new", path: "building" } : { kind: "start" };
        if (this.engine.native) await this.engine.native.newWindow(req);
        else if (req.kind === "new") await this.newDocument(req.path);
        else if (req.kind === "sample") await this.openSample("Cedar House");
        else { this.showStart = true; this.emit("start"); }
        break;
      }
      case "panels": this.showPanels = !this.showPanels; save("showPanels", this.showPanels); this.emit("panel"); break;
      case "deselectAll": await this.tryCall("select.set", { ids: [] }); await this.refresh(["selection"]); break;
      case "openURL": if (/^https:\/\//.test(v)) { if (this.engine.native) await this.engine.native.openExternal(v); else window.open(v, "_blank"); } break;
      case "view": await this.runCommand(`${v.toUpperCase()}VIEW`); break;
      case "ui": if (this.uiHooks.ui?.(a.slice(4))) break; this.print(`${a.slice(4)} is part of the Mac interface and is not in the Windows app yet.`); break;
      default: await this.runCommand(k.toUpperCase());
    }
  }
}
