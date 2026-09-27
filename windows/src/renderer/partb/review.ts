// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Review panels (ReviewPanels.swift): Markups / issues (filter, search, reply, resolve, zoom to, select linked, add around
// the selection, draw a cloud, BCF), Compare Drawings with the coloured overlay on the plan (added green, removed red
// dashed, modified yellow; save overlay drawing, CSV) and sheet Revision Clouds.
import type { App } from "../app";
import { h, clear, button, iconButton, field, segmented, picker, checkbox, spacer, ToolWindow, ico, help } from "./ui";
import * as N from "./native";
import type { PlanHooks } from "./index";

/** Shows a region of the plan: plan view (and level), zoomed to the box with a 25 % margin (ReviewUI.zoom). */
export async function zoomTo(app: App, plan: PlanHooks, box: number[] | null, level?: number | null) {
  if (!box || box.length < 4) return;
  if (level !== undefined && level !== null && app.info && app.info.currentLevelId !== level) {
    const name = app.info.levels.find((l) => l.id === level)?.name;
    if (name) { await app.tryCall("panel.set", { panel: "levels", key: "current", value: name }); await app.refresh(["document", "levels"]); }
  }
  if (app.mode === "3D" || app.mode === "Sheet") { app.activeLayout = 0; app.setUI("mode", "2D"); }
  const w = box[2] - box[0], hh = box[3] - box[1], m = Math.max(w, hh, 1) * 0.25;
  setTimeout(() => plan.zoomTo([box[0] - m, box[1] - m, box[2] + m, box[3] + m]), 30);
}

// ---- Markups (MarkupPanel) ----

export function showMarkups(app: App, plan: PlanHooks) {
  ToolWindow.show("markups", "Markups", { w: 420, h: 560, minW: 360, minH: 420 }, (w) => { new MarkupPanel(app, plan, w.body); });
}

let markupView: MarkupPanel | null = null;
let markupHooked = false;

class MarkupPanel {
  private filter: "Open" | "Resolved" | "All" = "Open";
  private query = "";
  private selected: string | null = null;
  private reply = "";
  private newTitle = "";
  private newComment = "";
  private data: any = { markups: [] };
  private counts = h("span", { class: "pb-small pb-dim" });
  private listEl = h("div", { class: "pb-scroll", style: { flex: "1", minHeight: "160px" } });
  private bottom = h("div", { style: { padding: "8px" } });
  constructor(private app: App, private plan: PlanHooks, host: HTMLElement) {
    const search = h("input", { class: "pb-field", placeholder: "Search comments, authors, replies", style: { flex: "1", border: "0", background: "transparent" } }) as HTMLInputElement;
    search.addEventListener("input", () => { this.query = search.value; this.render(); });
    search.addEventListener("keydown", (e) => e.stopPropagation());
    const seg = segmented(["Open", "Resolved", "All"], this.filter, (v) => { this.filter = v; this.render(); });
    seg.style.width = "200px";
    host.append(h("div", { class: "pb-row", style: { padding: "8px" } }, seg, spacer(), this.counts),
      h("div", { class: "pb-row pb-field", style: { margin: "0 8px", height: "26px", padding: "0 6px" } }, h("span", { class: "pb-dim", style: { display: "flex" } }, ico("magnifyingglass", 12)), search),
      h("div", { style: { height: "6px" } }), this.listEl, h("div", { class: "pb-hsep" }), this.bottom);
    this.load();
    markupView = this;
    if (!markupHooked) { markupHooked = true; app.on("doc", () => { if (ToolWindow.isOpen("markups")) markupView?.load(); }); }
  }
  async load() { this.data = (await this.app.tryCall("markup.list")) ?? { markups: [] }; this.render(); }
  private shown(): any[] {
    const q = this.query.trim().toLowerCase();
    return (this.data.markups ?? []).filter((m: any) => (this.filter === "All" || (this.filter === "Open") === !m.resolved)
      && (!q || `${m.title} ${m.comment} ${m.author} ${(m.replies ?? []).map((r: any) => r.text).join(" ")}`.toLowerCase().includes(q)));
  }
  private async edit(p: any) { const r = await this.app.tryCall("markup.edit", p); if (r?.list) this.data = r.list; await this.app.refresh(["document"]); this.render(); return r; }
  private render() {
    const all: any[] = this.data.markups ?? [];
    this.counts.textContent = `${all.filter((m) => !m.resolved).length} open · ${all.filter((m) => m.resolved).length} resolved`;
    clear(this.listEl);
    for (const m of this.shown()) {
      const icon = h("span", { style: { color: m.resolved ? "#34C759" : "var(--accent)", display: "flex", paddingTop: "2px" } }, ico(m.resolved ? "checkmark.circle.fill" : "exclamationmark.bubble.fill", 13));
      const n = (m.replies ?? []).length;
      const row = h("div", { class: "pb-list-row soft" + (this.selected === m.id ? " sel" : ""), style: { alignItems: "flex-start", padding: "4px 8px", gap: "6px" } }, icon,
        h("div", { class: "pb-col", style: { gap: "2px", minWidth: "0" } }, h("div", { style: { fontWeight: "600", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }, text: m.title || m.comment }),
          h("div", { class: "pb-small pb-dim", text: `${m.author} · ${String(m.date).slice(0, 10)}${n ? ` · ${n} repl${n === 1 ? "y" : "ies"}` : ""}` })));
      row.addEventListener("click", () => { this.selected = this.selected === m.id ? null : m.id; this.render(); });
      row.addEventListener("dblclick", () => this.zoom(m));
      this.listEl.append(row);
    }
    clear(this.bottom);
    const m = all.find((x) => x.id === this.selected);
    if (m) this.detail(m); else this.addForm();
  }
  private zoom(m: any) {
    const hgt = m.view?.height > 0 ? m.view.height : m.bounds ? m.bounds[3] - m.bounds[1] : 1000;
    const c = m.view?.center ?? [0, 0];
    const box = m.bounds ?? [c[0] - hgt * 0.8, c[1] - hgt / 2, c[0] + hgt * 0.8, c[1] + hgt / 2];
    zoomTo(this.app, this.plan, box, m.level);
    this.app.tryCall("select.set", { ids: m.entities ?? [] }).then(() => this.app.refresh(["selection"]));
  }
  private detail(m: any) {
    const b = this.bottom;
    const replyField = field({ value: this.reply, placeholder: "Reply…", flex: true, onInput: (v) => { this.reply = v; replyBtn.disabled = !v.trim(); }, onCommit: () => send() });
    const send = async () => { const t = this.reply.trim(); if (!t) return; this.reply = ""; await this.edit({ op: "reply", id: m.id, text: t }); };
    const replyBtn = button("Reply", { compact: true, disabled: !this.reply.trim(), onClick: send });
    b.append(h("div", { class: "pb-col", style: { gap: "6px" } },
      m.title ? h("div", { style: { fontWeight: "600" }, text: m.title }) : null,
      h("div", { style: { userSelect: "text" }, text: m.comment }),
      h("div", { class: "pb-small pb-dim", text: `${m.author} · ${m.date}${(m.elements ?? []).length ? " · linked: " + m.elements.map((x: number) => "#" + x).join(", ") : ""}` }),
      ...(m.replies ?? []).map((r: any) => h("div", { class: "pb-small", text: `↳ ${r.author} (${String(r.date).slice(0, 10)}): ${r.text}` })),
      h("div", { class: "pb-row" }, replyField, replyBtn),
      h("div", { class: "pb-row", style: { gap: "6px" } },
        button(m.resolved ? "Reopen" : "Resolve", { compact: true, onClick: () => this.edit({ op: "status", id: m.id, resolved: !m.resolved }) }),
        button("Zoom To", { compact: true, onClick: () => this.zoom(m) }),
        button("Select Linked", { compact: true, disabled: !(m.elements ?? []).length, onClick: async () => { await this.app.tryCall("select.set", { ids: m.elements }); await this.app.refresh(["selection"]); } }),
        spacer(),
        button("Delete", { compact: true, onClick: async () => { this.selected = null; await this.edit({ op: "remove", id: m.id }); } }),
        button("New…", { compact: true, onClick: () => { this.selected = null; this.render(); } }))));
  }
  private addForm() {
    const around = button("Around Selection", { compact: true, disabled: !this.newComment.trim() || !this.app.selection.ids.length, help: "Clouds the selected objects and links them to the markup",
      onClick: async () => {
        const r = await this.edit({ op: "addAroundSelection", title: this.newTitle, comment: this.newComment });
        if (r?.id) { this.selected = r.id; this.newComment = ""; this.newTitle = ""; this.filter = "Open"; this.render(); }
      } });
    const upd = () => { around.disabled = !this.newComment.trim() || !this.app.selection.ids.length; };
    this.bottom.append(h("div", { class: "pb-col", style: { gap: "6px" } },
      h("div", { style: { fontWeight: "600" }, text: "New markup" }),
      field({ value: this.newTitle, placeholder: "Title (optional)", onInput: (v) => { this.newTitle = v; } }),
      field({ value: this.newComment, placeholder: "Comment", onInput: (v) => { this.newComment = v; upd(); } }),
      h("div", { class: "pb-row", style: { gap: "6px" } }, around,
        button("Draw Cloud…", { compact: true, help: "Pick two corners on the plan, then type the comment on the command line", onClick: () => { if (this.app.mode === "3D") this.app.setUI("mode", "2D"); this.app.runCommand("MARKUP Add"); } }),
        spacer(),
        button("Export BCF…", { compact: true, onClick: () => this.app.runCommand("BCFOUT") }),
        button("Import BCF…", { compact: true, onClick: () => this.app.runCommand("BCFIN") }))));
  }
}

// ---- Compare drawings (ComparePanel + CompareOverlay) ----

class CompareOverlay {
  data: any = null;
  path: string | null = null;
  visible = true;
  kinds = new Set(["added", "removed", "modified"]);
  private cv: HTMLCanvasElement | null = null;
  private raf = 0;
  private last = "";
  constructor(private plan: PlanHooks) {}
  set(data: any, path: string | null) { this.data = data; this.path = path; this.visible = true; this.ensure(); }
  clear() { this.data = null; this.path = null; this.cv?.remove(); this.cv = null; cancelAnimationFrame(this.raf); }
  private ensure() {
    if (this.cv && this.cv.isConnected) { this.last = ""; return; }
    this.cv = h("canvas", { style: { position: "absolute", inset: "0", width: "100%", height: "100%", pointerEvents: "none", zIndex: "3" } }) as HTMLCanvasElement;
    const tick = () => { this.paint(); this.raf = requestAnimationFrame(tick); };
    this.raf = requestAnimationFrame(tick);
  }
  private paint() {
    const host = this.plan.el();
    if (!this.cv || !host) return;
    if (this.cv.parentElement !== host) host.append(this.cv);
    const v = this.plan.view();
    const key = `${v.cx},${v.cy},${v.scale},${host.clientWidth},${host.clientHeight},${this.visible},${[...this.kinds].join()}`;
    if (key === this.last) return;
    this.last = key;
    const dpr = devicePixelRatio || 1, w = host.clientWidth, hh = host.clientHeight;
    this.cv.width = w * dpr; this.cv.height = hh * dpr;
    const g = this.cv.getContext("2d")!;
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, w, hh);
    if (!this.visible || !this.data) return;
    const toView = (p: number[]) => [(p[0] - v.cx) * v.scale + w / 2, hh / 2 - (p[1] - v.cy) * v.scale];
    g.lineWidth = 2.5;
    for (const s of this.data.shapes ?? []) {
      if (!this.kinds.has(s.kind)) continue;
      g.strokeStyle = this.data.colors?.[s.kind] ?? "#ffffff";
      g.globalAlpha = 0.95;
      g.setLineDash(s.kind === "removed" ? [6, 4] : []);
      for (const pl of s.polylines ?? []) {
        if (pl.length < 2) continue;
        g.beginPath();
        const a = toView(pl[0]); g.moveTo(a[0], a[1]);
        for (const q of pl.slice(1)) { const b = toView(q); g.lineTo(b[0], b[1]); }
        g.stroke();
      }
    }
  }
  refresh() { this.last = ""; }
}
let overlay: CompareOverlay | null = null;

export function showCompare(app: App, plan: PlanHooks) {
  overlay ??= new CompareOverlay(plan);
  const ov = overlay;
  const w = ToolWindow.show("compare", "Compare Drawings", { w: 440, h: 520, minW: 380, minH: 360 }, (win) => {
    const body = h("div", { class: "pb-col", style: { padding: "10px", gap: "8px", flex: "1", minHeight: "0" } });
    win.body.append(body);
    let error = "";
    const render = () => {
      clear(body);
      const d = ov.data;
      body.append(h("div", { class: "pb-row" }, button("Compare With…", { onClick: choose }), ov.path ? h("span", { class: "pb-dim", style: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }, text: N.basename(ov.path) }) : null, spacer(),
        d ? button("Clear", { compact: true, onClick: () => { ov.clear(); render(); } }) : null));
      if (error) body.append(h("div", { class: "pb-small", style: { color: "#E5534B" }, text: error }));
      if (!d) {
        body.append(h("div", { class: "pb-dim", text: "Choose an older version (.archi, .dxf, .ifc…) to see what changed: added objects in green, removed in red (dashed), modified in yellow, drawn over the plan." }));
        return;
      }
      const toggles = h("div", { class: "pb-row", style: { gap: "12px" } }, checkbox("Overlay", ov.visible, (v) => { ov.visible = v; ov.refresh(); }));
      for (const k of ["added", "removed", "modified"]) {
        const c = checkbox("", ov.kinds.has(k), (v) => { if (v) ov.kinds.add(k); else ov.kinds.delete(k); ov.refresh(); render(); });
        c.append(h("span", { style: { width: "8px", height: "8px", borderRadius: "50%", background: d.colors?.[k] ?? "#fff", display: "inline-block" } }), h("span", { class: "pb-small", text: `${k[0].toUpperCase() + k.slice(1)} ${d.counts?.[k] ?? 0}` }));
        toggles.append(c);
      }
      body.append(toggles);
      if (d.identical) body.append(h("div", { class: "pb-dim", text: "The drawings are identical." }));
      if ((d.layersAdded ?? []).length || (d.layersRemoved ?? []).length) body.append(h("div", { class: "pb-small pb-dim", text: `Layers: +${d.layersAdded.join(", ")} −${d.layersRemoved.join(", ")}` }));
      const listEl = h("div", { class: "pb-scroll", style: { flex: "1" } });
      for (const s of d.shapes ?? []) {
        if (!ov.kinds.has(s.kind)) continue;
        const r = h("div", { class: "pb-list-row", style: { gap: "6px" } }, h("span", { style: { width: "8px", height: "8px", borderRadius: "50%", background: d.colors?.[s.kind], flex: "none" } }),
          h("span", { text: `${s.type} #${s.id}` }), h("span", { class: "pb-small pb-dim", text: s.layer }), spacer(),
          (s.fields ?? []).length ? h("span", { class: "pb-small pb-dim", text: s.fields.join(", ") }) : null);
        r.addEventListener("click", async () => { await zoomTo(app, plan, s.bounds, s.level); if (s.kind !== "removed") { await app.tryCall("select.set", { ids: [s.id] }); await app.refresh(["selection"]); } });
        listEl.append(r);
      }
      body.append(listEl, h("div", { class: "pb-row" },
        button("Save Overlay Drawing…", { compact: true, onClick: async () => { const out = await N.saveFile(app, "Save Overlay Drawing", "compare-overlay.archi", [{ name: "Archi", extensions: ["archi"] }]); if (out && ov.path) { const r = await app.tryCall("compare.save", { path: ov.path, out }); if (!r) error = `Cannot write ${out}`; render(); } } }),
        button("Export CSV…", { compact: true, onClick: async () => { const out = await N.saveFile(app, "Export CSV", "compare.csv", [{ name: "CSV", extensions: ["csv"] }]); if (out) { try { await N.writeText(out, d.csv ?? ""); } catch { error = `Cannot write ${out}`; render(); } } } })));
    };
    const choose = async () => {
      const p = await N.openFile(app, "Choose the other (older) version of the drawing", [{ name: "Drawings", extensions: ["archi", "archiz", "dxf", "dwg", "ifc", "ifczip"] }, { name: "All files", extensions: ["*"] }]);
      if (!p) return;
      try { const d = await app.call("compare.run", { path: p }); ov.set(d, p); error = ""; }
      catch (e: any) { error = `Cannot read ${N.basename(p)}: ${e?.message ?? e}`; }
      render();
    };
    render();
  });
  w.onClose = () => { ov.clear(); };
}

// ---- Revision clouds (RevisionCloudPanel) ----

export function showRevisionClouds(app: App) {
  ToolWindow.show("revisionClouds", "Revision Clouds", { w: 420, h: 480, minW: 380, minH: 360 }, (win) => {
    const body = h("div", { class: "pb-col", style: { padding: "10px", gap: "8px", flex: "1", minHeight: "0" } });
    win.body.append(body);
    let sheet = 0, code = "", note = "", target = -1, rx = "20", ry = "20", rw = "60", rh = "40";
    const render = async () => {
      const d = await app.tryCall("revcloud.list");
      clear(body);
      const sheets = d?.sheets ?? [];
      if (!sheets.length) { body.append(h("div", { class: "pb-dim", text: "The drawing has no sheets. Create a layout first." })); return; }
      const li = Math.min(Math.max(sheet, 0), sheets.length - 1);
      const revs: string[] = sheets[li].revisions ?? [];
      body.append(h("div", { class: "pb-row" }, h("span", { text: "Sheet" }), picker(sheets.map((s: any) => ({ value: String(s.index), label: s.name })), String(li), (v) => { sheet = Number(v); target = -1; render(); })));
      const codeF = field({ value: code, placeholder: revs[revs.length - 1] ?? "A", width: 60, onInput: (v) => { code = v; } });
      body.append(h("div", { class: "pb-row" }, h("span", { text: "Revision" }), codeF,
        revs.length ? (() => { const b = button("Sheet revisions", { compact: true }); b.addEventListener("click", () => import("./ui").then(({ showMenu }) => showMenu(revs.map((r) => ({ title: r, action: () => { code = r; codeF.value = r; } })), b))); return b; })() : null,
        field({ value: note, placeholder: "Note", flex: true, onInput: (v) => { note = v; } })));
      const vpOpts = [{ value: "-1", label: "Rectangle (mm on paper)" }, ...Array.from({ length: sheets[li].viewports ?? 0 }, (_, i) => ({ value: String(i), label: `Viewport ${i + 1}` }))];
      body.append(h("div", { class: "pb-row" }, h("span", { text: "Around" }), picker(vpOpts, String(target), (v) => { target = Number(v); render(); })));
      if (target < 0) {
        const f = (l: string, v: string, set: (x: string) => void) => h("div", { class: "pb-row", style: { gap: "2px" } }, h("span", { class: "pb-small pb-dim", text: l }), field({ value: v, width: 52, onInput: set }));
        body.append(h("div", { class: "pb-row" }, f("x", rx, (v) => { rx = v; }), f("y", ry, (v) => { ry = v; }), f("w", rw, (v) => { rw = v; }), f("h", rh, (v) => { rh = v; })));
      }
      body.append(h("div", {}, button("Add Revision Cloud", { onClick: async () => {
        const p: any = { layout: li, code, note };
        if (target >= 0) p.viewport = target; else { const r = [rx, ry, rw, rh].map(Number); if (r.some((x) => !isFinite(x)) || r[2] <= 0 || r[3] <= 0) return; p.rect = r; }
        await app.tryCall("revcloud.add", p);
        await app.refresh(["document"]);
        render();
      } })), h("div", { class: "pb-hsep" }));
      const clouds = d?.clouds ?? [];
      body.append(h("div", { style: { fontWeight: "600" }, text: `${clouds.length} cloud(s)` }));
      const listEl = h("div", { class: "pb-scroll", style: { flex: "1" } });
      for (const c of clouds) {
        const open = iconButton("arrow.right.circle", "Open the sheet", () => { app.activeLayout = c.layout + 1; app.setUI("mode", "Sheet"); });
        const del = iconButton("trash", "Delete the cloud and its tag", async () => { await app.tryCall("revcloud.remove", { id: c.id }); await app.refresh(["document"]); render(); });
        listEl.append(h("div", { class: "pb-list-row", style: { gap: "6px" } }, h("span", { style: { color: "#E5534B", display: "flex" } }, ico("cloud", 12)), h("span", { text: `${c.sheet} · rev ${c.code}` }),
          c.note ? h("span", { class: "pb-small pb-dim", style: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }, text: c.note }) : null, spacer(), open, del));
      }
      body.append(listEl);
      for (const r of d?.counts ?? []) body.append(h("div", { class: "pb-small pb-dim", text: `Rev ${r.code}: ${r.clouds} cloud(s) on ${r.sheets.join(", ")}` }));
    };
    render();
  });
  void help;
}
