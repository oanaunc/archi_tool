// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Node editor window (NodeEditorView.swift) and graph player (GraphPlayer.swift): typed nodes on a grid canvas, links
// dragged from outputs to inputs, groups and sticky notes, named graphs stored in the drawing, JSON / script export,
// node packages, Live baking, 3D and plan previews. The graph is evaluated by the engine (graph.evaluate, portable
// ArchiCore NodeGraph), so the results are identical to the Mac.
import type { App } from "../app";
import { h, clear, button, iconButton, menuButton, segmented, slider, toggleSwitch, spacer, vsep, ToolWindow, promptText, ico, help, fmt, type MenuItem } from "./ui";
import * as G from "./node-graph";
import * as N from "./native";
import { MeshPreview } from "./mesh-preview";
import { paintFitted } from "./plan-paint";

const PORT_COLORS: Record<G.PortType, string> = { number: "rgb(115,191,255)", point: "rgb(128,230,140)", geometry: "#F5C518", element: "rgb(242,140,89)" };
const FRAME_COLORS = ["#F5C418", "#3478F6", "#34C759", "#AF52DE", "#FF9500", "#30B0C7"];

export function showNodeEditor(app: App) {
  const title = `Node Editor — ${app.info?.title ?? "Untitled"}`;
  ToolWindow.show("nodeEditor", title, { w: 1180, h: 720, minW: 780, minH: 420 }, (w) => { new NodeEditor(app, w.body); });
}

class NodeEditor {
  private g: G.Graph = G.empty();
  private live = false;
  private previewMode: "3D" | "Plan" = "3D";
  private status = "";
  private ev: any = null;
  private evalSeq = 0;
  private bakeTimer = 0;
  private toolbar = h("div", { class: "pb-row", style: { padding: "6px 10px", flexWrap: "wrap", rowGap: "4px" } });
  private scroller = h("div", { style: { flex: "1", overflow: "auto", minWidth: "520px", background: "#212121" } });
  private canvas = h("div", { class: "pb-nodecanvas" });
  private svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  private previewHost = h("div", { style: { flex: "1", display: "flex", minHeight: "0" } });
  private mesh = new MeshPreview("#1A1A1A");
  private planCanvas = h("canvas") as HTMLCanvasElement;
  private planLabel = h("div", { class: "pb-small pb-dim", style: { position: "absolute", left: "6px", bottom: "6px" } });
  private drag: { from: number; x: number; y: number } | null = null;

  constructor(private app: App, host: HTMLElement) {
    this.svg.setAttribute("width", "2400"); this.svg.setAttribute("height", "1600");
    Object.assign(this.svg.style, { position: "absolute", left: "0", top: "0", pointerEvents: "none", overflow: "visible" });
    this.scroller.append(this.canvas);
    const pv = h("div", { style: { width: "340px", minWidth: "260px", display: "flex", flexDirection: "column", background: "#1A1A1A" } },
      h("div", { style: { padding: "6px", display: "flex", justifyContent: "center" } }, segmented(["3D", "Plan"], this.previewMode, (v) => { this.previewMode = v; this.showPreview(); this.evaluate(); })),
      this.previewHost);
    host.append(this.toolbar, h("div", { class: "pb-hsep" }), h("div", { style: { flex: "1", display: "flex", minHeight: "0" } }, this.scroller, h("div", { class: "pb-vsep" }), pv));
    this.showPreview();
    this.load();
  }

  private async load() {
    const r = await this.app.tryCall("graph.get");
    this.g = G.normalize(r?.graph ?? r?.sample ?? this.sample());
    this.changed(false);
  }
  private sample(): G.Graph {
    const g = G.empty();
    const hN = G.add(g, "number", 20, 40); g.nodes[0].params = { value: 3000, min: 500, max: 12000 };
    const p = G.add(g, "polygon", 20, 150); g.nodes[1].params = { radius: 300, sides: 8 };
    const e = G.add(g, "extrude", 240, 90);
    const a = G.add(g, "array", 460, 90);
    G.connect(g, p, e, "profile"); G.connect(g, hN, e, "height"); G.connect(g, e, a, "geometry");
    return g;
  }

  /** Every edit: redraw, evaluate (engine) and, with Live on, bake after 350 ms. */
  private changed(bake = true) {
    this.render();
    this.evaluate();
    if (bake && this.live) { clearTimeout(this.bakeTimer); this.bakeTimer = window.setTimeout(() => this.bake(), 350); }
  }

  private async evaluate() {
    const seq = ++this.evalSeq;
    const r = await this.app.tryCall("graph.evaluate", { graph: this.g, preview: this.previewMode === "3D" ? "3D" : "plan" });
    if (seq !== this.evalSeq) return;
    this.ev = r;
    this.renderToolbar();
    this.renderNodesState();
    this.renderLinks();
    if (r) {
      if (this.previewMode === "3D") { this.mesh.message = "No output"; this.mesh.set(r.meshes ?? [], false); }
      else this.paintPlan();
    }
  }

  private showPreview() {
    clear(this.previewHost);
    if (this.previewMode === "3D") { this.previewHost.append(this.mesh.el); requestAnimationFrame(() => this.mesh.draw()); }
    else { this.previewHost.append(h("div", { style: { position: "relative", flex: "1" } }, this.planCanvas, this.planLabel)); requestAnimationFrame(() => this.paintPlan()); }
  }
  private paintPlan() {
    const host = this.planCanvas.parentElement;
    if (!host || !this.ev) return;
    const w = host.clientWidth || 300, hh = host.clientHeight || 300;
    const list = { items: this.ev.items ?? [] };
    paintFitted(this.planCanvas, list, w, hh, { background: "#1A1A1A", margin: 30 / Math.min(w, hh), color: "#F5C518" });
    this.planLabel.textContent = `${this.ev.objects ?? 0} object(s)${this.ev.elements ? `, ${this.ev.elements} element(s)` : ""}`;
  }

  // ---- toolbar ----
  private renderToolbar() {
    const t = this.toolbar;
    clear(t);
    const addMenu = (): MenuItem[] => {
      const out: MenuItem[] = [];
      for (const cat of G.CATEGORIES) {
        out.push({ header: cat });
        for (const k of G.KINDS.filter((x) => x.category === cat)) out.push({ title: k.title, action: () => { const c = this.g.nodes.length; G.add(this.g, k.kind, 40 + (c % 6) * 36, 40 + (c % 8) * 30); this.changed(); } });
      }
      return out;
    };
    const ev = this.ev;
    const objects = ev?.objects ?? 0, elements = ev?.elements ?? 0, errors = ev?.errors ?? 0;
    const counts = h("span", { class: "pb-small", style: { color: errors ? "var(--danger)" : "var(--dim)" }, text: `${this.g.nodes.length} nodes · ${objects} objects · ${elements} elements${errors ? ` · ${errors} error(s)` : ""}` });
    t.append(
      menuButton("Add Node", "plus.circle", addMenu),
      button("Sample", { icon: "wand.and.stars", compact: true, onClick: () => { this.g = this.sample(); this.changed(); } }),
      button("Group", { icon: "rectangle.dashed", compact: true, help: "Frame the ungrouped nodes in a titled group; drag its title to move the group with its nodes",
        onClick: () => { const ids = this.g.nodes.filter((n) => !this.g.groups.some((f) => G.frameContains(f, n))).map((n) => n.id); G.addGroup(this.g, `Group ${this.g.groups.length + 1}`, ids); this.changed(); } }),
      button("Comment", { icon: "note.text", compact: true, help: "Add a sticky note to the canvas", onClick: () => { G.addComment(this.g, "Note", 60 + this.g.comments.length * 24, 60); this.changed(); } }),
      button("Clear", { icon: "trash", compact: true, onClick: () => { this.g = G.empty(); this.changed(); } }),
      menuButton("Graphs", "folder", () => this.graphsMenu(), "Named graphs stored in the drawing, JSON import/export"),
      menuButton("Packages", "shippingbox", () => this.packagesMenu(), "Custom node packages: reusable graph snippets shared as .archinodes files"),
      h("div", { class: "pb-vsep", style: { height: "16px", alignSelf: "center" } }),
      toggleSwitch("Live", this.live, (v) => { this.live = v; if (v) this.changed(); }, "Update the drawing on every change (the baked objects are replaced)"),
      button("Bake to Drawing", { icon: "square.and.arrow.down.on.square", prominent: true, disabled: !objects && !elements, help: "Write the output geometry into the drawing (one undo step; replaces the previous bake)", onClick: () => this.bake() }),
      button("Save Graph", { icon: "square.and.arrow.down", compact: true, help: "Store the graph in the drawing (.archi)", onClick: () => this.saveGraph() }),
      spacer(),
      this.status ? h("span", { class: "pb-status", text: this.status }) : "",
      counts);
  }
  private setStatus(s: string) { this.status = s; this.renderToolbar(); }

  private graphsCache: string[] = [];
  private graphsMenu(): MenuItem[] {
    this.app.tryCall("graph.get").then((r) => { this.graphsCache = r?.names ?? []; });
    const names = this.graphsCache;
    const items: MenuItem[] = names.length ? names.map((n) => ({ title: `Open “${n}”`, action: async () => { const g = await this.app.tryCall("graph.load", { name: n }); if (g) { this.g = G.normalize(g); this.changed(); this.setStatus(`Opened graph “${n}”.`); } } }))
      : [{ title: "No named graphs in this drawing", disabled: true }];
    items.push({ separator: true },
      { title: "Save As…", action: () => this.saveNamed() },
      { title: "Delete", disabled: !names.length, submenu: names.map((n) => ({ title: n, action: async () => { await this.app.tryCall("graph.delete", { name: n }); this.setStatus(`Deleted graph “${n}”.`); this.graphsCache = this.graphsCache.filter((x) => x !== n); } })) },
      { separator: true },
      { title: "Export JSON…", action: () => this.exportJSON() },
      { title: "Export as Script…", action: () => this.exportScript() },
      { title: "Open as Script in Console", action: () => this.openInConsole() },
      { title: "Import JSON…", action: () => this.importJSON() });
    return items;
  }
  async refreshNames() { const r = await this.app.tryCall("graph.get"); this.graphsCache = r?.names ?? []; }

  private async saveNamed() {
    await this.refreshNames();
    const name = (await promptText("Save graph as", "Named graphs are stored in the drawing (.archi) and can be opened from the Graphs menu.", `Graph ${this.graphsCache.length + 1}`))?.trim();
    if (!name) return;
    await this.app.tryCall("graph.save", { graph: this.g, name });
    this.graphsCache = [...new Set([...this.graphsCache, name])].sort();
    this.setStatus(`Graph saved as “${name}”.`);
  }
  private async saveGraph() { await this.app.tryCall("graph.save", { graph: this.g }); this.setStatus("Graph saved in the drawing."); }
  private async bake() {
    const r = await this.app.tryCall("graph.bake", { graph: this.g });
    if (r) this.setStatus(`Baked ${(r.ids ?? []).length} object(s) on layer NODES.`);
    await this.app.refresh(["document"]);
  }
  private async exportJSON() {
    const p = await N.saveFile(this.app, "Export Graph", "graph.json", [{ name: "JSON", extensions: ["json"] }]);
    if (!p) return;
    try { await N.writeText(p, JSON.stringify(this.g, null, 2)); this.setStatus(`Exported ${N.basename(p)}.`); } catch (e: any) { this.setStatus(String(e?.message ?? e)); }
  }
  private async exportScript() {
    const p = await N.saveFile(this.app, "Export as Script", "graph.js", [{ name: "JavaScript", extensions: ["js"] }]);
    if (!p) return;
    const js = await this.app.tryCall("graph.script", { graph: this.g, name: N.stem(p) });
    if (typeof js === "string") { await N.writeText(p, js); this.setStatus(`Exported ${N.basename(p)}.`); }
  }
  private async openInConsole() {
    const js = await this.app.tryCall("graph.script", { graph: this.g, name: "graph" });
    if (typeof js !== "string") return;
    localStorage.setItem("archi.script.code", js);
    document.dispatchEvent(new CustomEvent("archi:scriptConsole", { detail: { show: true, code: js } }));
    this.setStatus("The graph script is in the JavaScript console.");
  }
  private async importJSON() {
    const p = await N.openFile(this.app, "Import Graph", [{ name: "JSON", extensions: ["json"] }]);
    if (!p) return;
    try { const t = await N.readText(p); const j = JSON.parse(t ?? ""); if (!Array.isArray(j.nodes)) throw new Error(); this.g = G.normalize(j); this.changed(); this.setStatus(`Imported ${N.basename(p)}.`); }
    catch { this.setStatus("Not a node graph file."); }
  }

  // ---- packages ----
  private pkgCache: G.Package[] = [];
  private async installed(): Promise<G.Package[]> {
    const dir = (await N.paths()).nodePackages;
    await N.mkdir(dir);
    const out: G.Package[] = [];
    for (const f of await N.list(dir, [G.PACKAGE_EXT])) { if (f.dir) continue; try { out.push(G.decodePackage((await N.readText(f.path)) ?? "")); } catch { /* not a package */ } }
    return out.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: "base" }));
  }
  private packagesMenu(): MenuItem[] {
    this.installed().then((p) => { this.pkgCache = p; });
    const items: MenuItem[] = this.pkgCache.length ? this.pkgCache.map((p) => ({
      title: `${p.name} ${p.version}`,
      submenu: [...p.snippets.map((s) => ({ title: s.name, action: () => {
        const x = this.g.nodes.length ? Math.max(...this.g.nodes.map((n) => n.x)) + 260 : 40;
        G.insert(this.g, s.graph, x, 40); this.changed(); this.setStatus(`Inserted “${s.name}” from ${p.name}.`);
      } })), { separator: true }, { title: "Remove Package", action: async () => { await N.remove(N.join((await N.paths()).nodePackages, p.name.replace(/\//g, "-") + "." + G.PACKAGE_EXT)); this.setStatus(`Removed ${p.name}.`); this.pkgCache = this.pkgCache.filter((x) => x !== p); } }],
    })) : [{ title: "No packages installed", disabled: true }];
    items.push({ separator: true },
      { title: "Save Graph as Package…", action: () => this.savePackage() },
      { title: "Install Package…", action: () => this.installPackage() },
      { title: "Show Library Folder", action: async () => { const d = (await N.paths()).nodePackages; await N.mkdir(d); await N.reveal(this.app, d); } });
    return items;
  }
  private async savePackage() {
    const p = await N.saveFile(this.app, "Save Graph as Package", "My Nodes." + G.PACKAGE_EXT, [{ name: "Node package", extensions: [G.PACKAGE_EXT] }]);
    if (!p) return;
    const pkg = G.makePackage(this.g, N.stem(p), this.app.info?.project ? "" : "");
    const text = G.encodePackage(pkg);
    await N.writeText(p, text);
    await N.writeText(N.join((await N.paths()).nodePackages, pkg.name.replace(/\//g, "-") + "." + G.PACKAGE_EXT), text);
    this.setStatus(`Package ${pkg.name}: ${pkg.snippets.length} snippet(s).`);
  }
  private async installPackage() {
    const p = await N.openFile(this.app, "Install Package", [{ name: "Node package", extensions: [G.PACKAGE_EXT] }, { name: "All files", extensions: ["*"] }]);
    if (!p) return;
    try {
      const pkg = G.decodePackage((await N.readText(p)) ?? "");
      await N.writeText(N.join((await N.paths()).nodePackages, pkg.name.replace(/\//g, "-") + "." + G.PACKAGE_EXT), G.encodePackage(pkg));
      this.setStatus(`Installed ${pkg.name} ${pkg.version}.`);
    } catch (e: any) { this.setStatus(String(e?.message ?? e)); }
  }

  // ---- canvas ----
  private nodeEls = new Map<number, HTMLElement>();

  private render() {
    clear(this.canvas);
    this.nodeEls.clear();
    for (const f of this.g.groups) this.canvas.append(this.frameEl(f));
    this.canvas.append(this.svg);
    for (const n of this.g.nodes) { const el = this.nodeEl(n); this.nodeEls.set(n.id, el); this.canvas.append(el); }
    for (const c of this.g.comments) this.canvas.append(this.commentEl(c));
    this.renderLinks();
    this.renderToolbar();
    this.renderNodesState();
  }

  private curve(p: { x: number; y: number }, q: { x: number; y: number }) {
    const dx = Math.max(40, Math.abs(q.x - p.x) * 0.5);
    return `M${p.x},${p.y} C${p.x + dx},${p.y} ${q.x - dx},${q.y} ${q.x},${q.y}`;
  }
  private renderLinks() {
    while (this.svg.firstChild) this.svg.removeChild(this.svg.firstChild);
    const errs = this.ev?.nodes ?? {};
    for (const l of this.g.links) {
      const a = G.node(this.g, l.from), b = G.node(this.g, l.to);
      if (!a || !b) continue;
      const pi = G.kindOf(b.kind).inputs.findIndex((x) => x.name === l.port);
      if (pi < 0) continue;
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("d", this.curve(G.outputPort(a), G.inputPort(b, pi)));
      path.setAttribute("fill", "none");
      path.setAttribute("stroke", errs[String(l.from)]?.error ? "#E5534B" : "rgba(245,197,24,0.85)");
      path.setAttribute("stroke-width", "2");
      this.svg.append(path);
    }
    if (this.drag) {
      const a = G.node(this.g, this.drag.from);
      if (a) {
        const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
        path.setAttribute("d", this.curve(G.outputPort(a), { x: this.drag.x, y: this.drag.y }));
        path.setAttribute("fill", "none"); path.setAttribute("stroke", "rgba(245,197,24,0.6)"); path.setAttribute("stroke-width", "2"); path.setAttribute("stroke-dasharray", "5 4");
        this.svg.append(path);
      }
    }
  }

  private renderNodesState() {
    const outs = new Set<number>(this.ev?.outputNodes ?? G.outputNodes(this.g));
    for (const n of this.g.nodes) {
      const el = this.nodeEls.get(n.id);
      if (!el) continue;
      const st = this.ev?.nodes?.[String(n.id)];
      el.classList.toggle("output", outs.has(n.id) && !st?.error);
      el.classList.toggle("error", !!st?.error);
      const foot = el.querySelector(".nfoot") as HTMLElement;
      if (foot) { foot.textContent = st?.error ?? st?.summary ?? "—"; foot.classList.toggle("err", !!st?.error); }
      const badge = el.querySelector(".outbadge") as HTMLElement;
      if (badge) badge.style.display = outs.has(n.id) ? "" : "none";
    }
  }

  private toCanvas(e: MouseEvent) { const r = this.canvas.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; }

  private nodeEl(n: G.GNode): HTMLElement {
    const k = G.kindOf(n.kind);
    const color = PORT_COLORS[k.output];
    const close = h("button", { class: "pb-ibtn", style: { width: "16px", height: "16px", color: "var(--dim)" } }, ico("xmark", 9, 2));
    help(close, "Delete node");
    close.addEventListener("click", (e) => { e.stopPropagation(); G.remove(this.g, n.id); this.changed(); });
    const out = h("div", { class: "out", style: { background: color } });
    help(out, "Drag to an input to connect");
    const badge = h("span", { class: "outbadge pb-accent", style: { display: "none" } }, ico("arrow.down.to.line", 9, 2));
    help(badge, "Output: previewed and baked");
    const head = h("div", { class: "nh", style: { background: color.replace("rgb(", "rgba(").replace(")", ",0.28)").replace("#F5C518", "rgba(245,197,24,0.28)") } },
      h("span", { text: k.title }), badge, spacer(), close, out);
    const el = h("div", { class: "pb-node", "data-node": String(n.id), style: { left: n.x + "px", top: n.y + "px" } }, head);
    head.addEventListener("mousedown", (e) => {
      if ((e.target as HTMLElement).closest(".out") || (e.target as HTMLElement).closest("button")) return;
      const x0 = e.clientX, y0 = e.clientY, nx = n.x, ny = n.y;
      const mv = (ev: MouseEvent) => { n.x = Math.max(0, nx + ev.clientX - x0); n.y = Math.max(0, ny + ev.clientY - y0); el.style.left = n.x + "px"; el.style.top = n.y + "px"; this.renderLinks(); };
      const up = () => { removeEventListener("mousemove", mv); removeEventListener("mouseup", up); this.changed(false); };
      addEventListener("mousemove", mv); addEventListener("mouseup", up); e.preventDefault();
    });
    out.addEventListener("mousedown", (e) => {
      e.stopPropagation(); e.preventDefault();
      const mv = (ev: MouseEvent) => { const p = this.toCanvas(ev); this.drag = { from: n.id, x: p.x, y: p.y }; this.renderLinks(); };
      const up = (ev: MouseEvent) => { removeEventListener("mousemove", mv); removeEventListener("mouseup", up); const p = this.toCanvas(ev); this.drag = null; this.finishLink(n.id, p); };
      addEventListener("mousemove", mv); addEventListener("mouseup", up);
    });
    k.inputs.forEach((p) => el.append(this.inputRow(n, p)));
    if (n.kind === "number") el.append(this.numberBody(n));
    el.append(h("div", { class: "nfoot", text: "—" }));
    return el;
  }

  private finishLink(from: number, at: { x: number; y: number }) {
    for (const n of this.g.nodes) {
      if (n.id === from) continue;
      const ins = G.kindOf(n.kind).inputs;
      for (let i = 0; i < ins.length; i++) {
        const c = G.inputPort(n, i);
        if (Math.hypot(c.x - at.x, c.y - at.y) < 16) {
          if (!G.connect(this.g, from, n.id, ins[i].name)) this.status = "Cannot connect: type mismatch or cycle."; else this.status = "";
          this.changed();
          return;
        }
      }
    }
    this.renderLinks();
  }

  private numField(n: G.GNode, key: string, def: number, width: number, onSet?: () => void): HTMLInputElement {
    const f = h("input", { class: "nf", style: { width: width + "px" } }) as HTMLInputElement;
    f.value = fmt(G.param(n, key, def), 3);
    f.addEventListener("keydown", (e) => { e.stopPropagation(); if (e.key === "Enter") f.blur(); });
    f.addEventListener("change", () => { const v = Number(f.value); if (isFinite(v)) { n.params[key] = v; onSet?.(); this.changed(); } else f.value = fmt(G.param(n, key, def), 3); });
    return f;
  }

  private inputRow(n: G.GNode, p: G.Port): HTMLElement {
    const linked = this.g.links.some((l) => l.to === n.id && l.port === p.name);
    const dot = h("div", { class: "in", style: { background: linked ? PORT_COLORS[p.type] : "#595959" } });
    help(dot, linked ? "Click to disconnect" : `${p.type} input`);
    dot.addEventListener("click", () => { if (linked) { G.disconnect(this.g, n.id, p.name); this.changed(); } });
    const r = h("div", { class: "nrow" }, dot, h("span", { class: "pn", text: p.name }));
    if (linked) r.append(h("span", { class: "pb-faint", style: { fontSize: "9.5px" }, text: "linked" }));
    else if (p.type === "number") r.append(this.numField(n, p.name, p.def, 96));
    else if (p.type === "point") r.append(this.numField(n, p.name + ".x", p.def, 36), this.numField(n, p.name + ".y", 0, 36), this.numField(n, p.name + ".z", 0, 30));
    else r.append(h("span", { class: "pb-faint", style: { fontSize: "9.5px" }, text: "connect" }));
    return r;
  }

  private numberBody(n: G.GNode): HTMLElement {
    const lo = G.param(n, "min", 0), hi = Math.max(G.param(n, "max", 10000), lo + 1e-6);
    const value = this.numField(n, "value", 1000, 58);
    const s = slider(G.param(n, "value", 1000), lo, hi, { onInput: (v) => { n.params.value = Math.round(v * 1000) / 1000; value.value = fmt(n.params.value, 3); this.evaluate(); if (this.live) { clearTimeout(this.bakeTimer); this.bakeTimer = window.setTimeout(() => this.bake(), 350); } } });
    s.style.minWidth = "60px";
    return h("div", { class: "numbody" },
      h("div", { class: "pb-row", style: { gap: "4px" } }, s, value),
      h("div", { class: "pb-row", style: { gap: "4px" } }, h("span", { class: "pb-faint", style: { fontSize: "9px" }, text: "min" }), this.numField(n, "min", 0, 50),
        h("span", { class: "pb-faint", style: { fontSize: "9px" }, text: "max" }), this.numField(n, "max", 10000, 58)));
  }

  private frameEl(f: G.GFrame): HTMLElement {
    const c = FRAME_COLORS[Math.abs(f.color) % FRAME_COLORS.length];
    const title = h("input", { value: f.title, placeholder: "Group" }) as HTMLInputElement;
    title.addEventListener("keydown", (e) => e.stopPropagation());
    title.addEventListener("change", () => { f.title = title.value; this.changed(false); });
    const count = h("span", { class: "pb-dim", style: { fontSize: "9px" }, text: `${G.members(this.g, f).length} nodes` });
    const pal = h("button", { class: "pb-ibtn", style: { width: "16px", height: "16px" } }, ico("paintpalette", 9));
    help(pal, "Change colour");
    pal.addEventListener("click", () => { f.color += 1; this.changed(false); });
    const del = h("button", { class: "pb-ibtn", style: { width: "16px", height: "16px" } }, ico("xmark", 9, 2));
    help(del, "Delete the group (keeps the nodes)");
    del.addEventListener("click", () => { this.g.groups = this.g.groups.filter((x) => x.id !== f.id); this.changed(false); });
    const head = h("div", { class: "fh", style: { background: hexA(c, 0.25) } }, title, count, pal, del);
    const rs = h("div", { class: "rs" }, ico("arrow.up.left.and.arrow.down.right", 9));
    const el = h("div", { class: "pb-frame", style: { left: f.x + "px", top: f.y + "px", width: f.width + "px", height: f.height + "px", background: hexA(c, 0.08), border: `1px solid ${hexA(c, 0.5)}` } }, head, rs);
    head.addEventListener("mousedown", (e) => {
      if ((e.target as HTMLElement).tagName === "INPUT" || (e.target as HTMLElement).closest("button")) return;
      let lx = e.clientX, ly = e.clientY;
      const mv = (ev: MouseEvent) => { G.moveGroup(this.g, f.id, ev.clientX - lx, ev.clientY - ly); lx = ev.clientX; ly = ev.clientY; this.render(); };
      const up = () => { removeEventListener("mousemove", mv); removeEventListener("mouseup", up); this.changed(false); };
      addEventListener("mousemove", mv); addEventListener("mouseup", up); e.preventDefault();
    });
    rs.addEventListener("mousedown", (e) => {
      const x0 = e.clientX, y0 = e.clientY, w0 = f.width, h0 = f.height;
      const mv = (ev: MouseEvent) => { f.width = Math.max(160, w0 + ev.clientX - x0); f.height = Math.max(80, h0 + ev.clientY - y0); el.style.width = f.width + "px"; el.style.height = f.height + "px"; count.textContent = `${G.members(this.g, f).length} nodes`; };
      const up = () => { removeEventListener("mousemove", mv); removeEventListener("mouseup", up); this.changed(false); };
      addEventListener("mousemove", mv); addEventListener("mouseup", up); e.preventDefault(); e.stopPropagation();
    });
    return el;
  }

  private commentEl(c: G.GComment): HTMLElement {
    const ta = h("textarea", { rows: 3, placeholder: "Comment" }) as HTMLTextAreaElement;
    ta.value = c.text;
    ta.addEventListener("keydown", (e) => e.stopPropagation());
    ta.addEventListener("change", () => { c.text = ta.value; this.changed(false); });
    const del = h("button", { class: "pb-ibtn", style: { width: "14px", height: "14px", color: "rgba(0,0,0,0.6)" } }, ico("xmark", 9, 2));
    del.addEventListener("click", () => { this.g.comments = this.g.comments.filter((x) => x.id !== c.id); this.changed(false); });
    const th = h("div", { class: "th" }, ico("note.text", 9), spacer(), del);
    const el = h("div", { class: "pb-note", style: { left: c.x + "px", top: c.y + "px", width: c.width + "px" } }, th, ta);
    th.addEventListener("mousedown", (e) => {
      if ((e.target as HTMLElement).closest("button")) return;
      const x0 = e.clientX, y0 = e.clientY, cx = c.x, cy = c.y;
      const mv = (ev: MouseEvent) => { c.x = Math.max(0, cx + ev.clientX - x0); c.y = Math.max(0, cy + ev.clientY - y0); el.style.left = c.x + "px"; el.style.top = c.y + "px"; };
      const up = () => { removeEventListener("mousemove", mv); removeEventListener("mouseup", up); this.changed(false); };
      addEventListener("mousemove", mv); addEventListener("mouseup", up); e.preventDefault();
    });
    return el;
  }
}

function hexA(hex: string, a: number) { const t = hex.replace("#", ""); return `rgba(${parseInt(t.slice(0, 2), 16)},${parseInt(t.slice(2, 4), 16)},${parseInt(t.slice(4, 6), 16)},${a})`; }

// ---- Graph player (GraphPlayerView) ----

export function showGraphPlayer(app: App) {
  ToolWindow.show("graphPlayer", "Graph Player", { w: 380, h: 420, minW: 300, minH: 240 }, (w) => {
    const body = h("div", { class: "pb-col pb-scroll", style: { padding: "14px", gap: "10px", flex: "1" } });
    w.body.append(body);
    let graphName = "Current";
    let values: Record<string, number> = {};
    let status = "";
    const render = async () => {
      const r = await app.tryCall("graph.get");
      const all: { name: string; graph: G.Graph }[] = [];
      if (r?.graph) all.push({ name: "Current", graph: G.normalize(r.graph) });
      for (const n of r?.names ?? []) if (r?.graphs?.[n]) all.push({ name: n, graph: G.normalize(r.graphs[n]) });
      clear(body);
      if (!all.length) { body.append(h("div", { class: "pb-dim", text: "No saved graphs. Build one in the Node Editor (NODEEDITOR) and save it." })); }
      else {
        const g = (all.find((x) => x.name === graphName) ?? all[0]).graph;
        const sel = h("select", { class: "pb-field" }) as HTMLSelectElement;
        for (const a of all) sel.append(h("option", { value: a.name, text: a.name }));
        sel.value = all.some((x) => x.name === graphName) ? graphName : all[0].name;
        sel.addEventListener("change", () => { graphName = sel.value; values = {}; render(); });
        body.append(h("div", { class: "pb-row" }, h("span", { text: "Graph" }), sel));
        const inputs = g.nodes.filter((n) => n.kind === "number").map((n) => {
          const lo = G.param(n, "min", 0), hi = G.param(n, "max", 10000);
          return { id: n.id, name: G.parameterName(g, n), value: G.param(n, "value", 0), min: Math.min(lo, hi), max: Math.max(lo, hi) };
        });
        if (!inputs.length) body.append(h("div", { class: "pb-dim", text: "This graph has no Number inputs." }));
        for (const inp of inputs) {
          const label = h("div", { text: `${inp.name}: ${fmt(values[inp.name] ?? inp.value, 2)}` });
          const s = slider(values[inp.name] ?? inp.value, inp.min, Math.max(inp.max, inp.min + 1e-9), { onInput: (v) => { values[inp.name] = v; label.textContent = `${inp.name}: ${fmt(v, 2)}`; } });
          s.style.width = "100%";
          body.append(h("div", { class: "pb-col", style: { gap: "2px" } }, label, s));
        }
        body.append(h("div", { class: "pb-row" }, button("Reset", { onClick: () => { values = {}; render(); } }), spacer(),
          button("Run", { prominent: true, onClick: async () => {
            const played = G.clone(g);
            for (const inp of inputs) { const v = values[inp.name] ?? values[String(inp.id)]; const n = played.nodes.find((x) => x.id === inp.id); if (v !== undefined && n) n.params.value = Math.min(Math.max(v, inp.min), inp.max); }
            const res = await app.tryCall("graph.bake", { graph: played, label: "Graph Player", store: false });
            status = `Baked ${(res?.ids ?? []).length} object(s).`;
            await app.refresh(["document"]);
            render();
          } })));
      }
      if (status) body.append(h("div", { class: "pb-small pb-dim", text: status }));
    };
    render();
  });
}
