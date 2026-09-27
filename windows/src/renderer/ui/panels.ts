// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Docked panel stack on the right (PanelsView.swift): 14 tabs in a 6-column icon grid, float / hide buttons, and the
// panel contents from the engine (panel.<name>): Properties, Layers, Levels, Browser, Materials, Tools, Sheets, History…
import type { App } from "../app";
import { renderLayersPanel } from "../dialogs";
import { h, clear } from "../dom";
import { icon } from "../icons";
import { help, showMenu } from "./menu";
import ui from "../data/ui.generated.json";

export const PANEL_SYMBOLS: Record<string, string> = {
  Properties: "slider.horizontal.3", Layers: "square.3.layers.3d", Levels: "building.2", Browser: "list.bullet.indent", Materials: "paintpalette",
  Tools: "square.grid.3x3.square", Sheets: "rectangle.stack", History: "clock.arrow.circlepath", Selection: "info.square", Navigator: "map",
  Alerts: "bell.badge", "Quick Props": "slider.horizontal.below.rectangle", Inspector: "list.bullet.rectangle", Content: "books.vertical.circle",
};
const PANELS: string[] = ((ui as any).panels as any[]).map((p) => (typeof p === "string" ? p : p.name ?? p.title)).filter(Boolean);
const METHOD: Record<string, string> = { "Quick Props": "quick" };

function humanize(name: string) {
  let out = "";
  [...name].forEach((ch, i) => {
    if (ch === "." || ch === "_") { out += " "; return; }
    if (ch >= "A" && ch <= "Z" && i > 0 && !/\s$/.test(out)) out += " ";
    out += i === 0 ? ch.toUpperCase() : ch;
  });
  return out.replace(/Id\b/g, "ID");
}

export class Panels {
  el: HTMLElement;
  private tabs: HTMLElement;
  private body: HTMLElement;
  private seq = 0;

  constructor(private app: App) {
    this.tabs = h("div", { class: "panel-tabs" });
    this.body = h("div", { class: "panel-body" });
    this.el = h("div", { class: "panels" }, this.tabs, h("div", { class: "hsep" }), this.body);
    this.renderTabs(); this.renderBody();
    app.on("ui", () => { this.renderTabs(); this.renderBody(); });
    app.on(["panel", "selection", "layers", "doc"], () => this.renderBody());
  }

  private renderTabs() {
    clear(this.tabs);
    const grid = h("div", { class: "grid" });
    for (const t of PANELS) {
      const b = h("button", { class: "ptab" + (t === this.app.panelTab ? " sel" : "") }, icon(PANEL_SYMBOLS[t] ?? "square", 13, 1.6), h("span", { class: "t", text: t }));
      help(b, `${t} — right-click to float`);
      b.addEventListener("click", () => this.app.setUI("panelTab", t));
      b.addEventListener("contextmenu", (e) => { e.preventDefault(); showMenu([{ title: `Float ${t} Panel`, action: () => this.app.runCommand(`FLOATPANEL ${t}`) }], { x: e.clientX, y: e.clientY }); });
      grid.append(b);
    }
    const fl = h("button", { class: "iconbtn" }, icon("macwindow.on.rectangle", 12)); help(fl, "Float this panel in its own window (FLOATPANEL)");
    fl.addEventListener("click", () => this.app.runCommand(`FLOATPANEL ${this.app.panelTab}`));
    const x = h("button", { class: "iconbtn" }, icon("xmark", 12, 2)); help(x, "Hide panels");
    x.addEventListener("click", () => this.app.setUI("showPanels", false));
    this.tabs.append(grid, h("div", { class: "side" }, fl, x));
  }

  private async renderBody() {
    const tab = this.app.panelTab;
    const seq = ++this.seq;
    const local = ["Browser", "Tools", "Selection", "Alerts", "Content", "Navigator"];
    const method = "panel." + (METHOD[tab] ?? tab.toLowerCase());
    let data: any = null, err = "";
    if (!local.includes(tab)) {
      try { data = await this.app.engine.call(method === "panel.quick" || method === "panel.inspector" ? "panel.properties" : method, {}); } catch (e: any) { err = e?.message ?? String(e); }
    }
    if (seq !== this.seq) return;
    const scroll = this.body.scrollTop;
    clear(this.body);
    if (tab === "Properties" || tab === "Quick Props" || tab === "Inspector") this.properties(data);
    else if (tab === "Layers") renderLayersPanel(this.body, data, (k, v) => this.set("layers", k, v));
    else if (tab === "Levels") this.levels(data);
    else if (tab === "Materials" && data) this.materials(data);
    else if (tab === "Sheets" && data) this.sheets(data);
    else if (tab === "History" && data) this.history(data);
    else if (local.includes(tab)) this.localPanel(tab);
    else if (data) this.generic(tab, data);
    else this.body.append(h("div", { class: "pempty", text: err ? `${tab} is not available yet: ${err}` : `No ${tab.toLowerCase()} data.` }));
    this.body.scrollTop = scroll;
  }

  private list(items: { label: string; meta?: string; icon?: string; color?: string; current?: boolean; act?: () => void; tip?: string }[]) {
    const box = h("div", { class: "plist" });
    for (const it of items) {
      const row = h("div", { class: "li" + (it.current ? " cur" : "") }, it.color ? h("span", { class: "swatch", style: { background: it.color } }) : it.icon ? icon(it.icon, 12) : h("span"),
        h("span", { class: "name", text: it.label }), h("span", { class: "meta", text: it.meta ?? "" }));
      if (it.act) row.addEventListener("click", it.act);
      if (it.tip) help(row, it.tip);
      box.append(row);
    }
    this.body.append(box);
  }
  private sheets(d: any) {
    const app = this.app;
    this.body.append(h("div", { class: "phdr", text: "Sheets" }));
    this.list([{ label: "Model", icon: "square.grid.3x3", current: (d.current ?? "Model") === "Model", act: () => { app.activeLayout = 0; app.setUI("mode", "2D"); } },
      ...(d.sheets ?? []).map((sh: any, i: number) => ({ label: sh.name, meta: sh.paper ? `${sh.paper.name} · ${sh.viewports ?? 0} vp` : "", icon: "doc.richtext", current: sh.name === d.current,
        act: () => this.set("sheets", "current", sh.name).then(() => { app.activeLayout = i + 1; app.setUI("mode", "Sheet"); }) }))]);
    const tb = h("div", { class: "ptoolbar" });
    const add = h("button", { class: "flatbtn", text: "New Sheet" }); add.addEventListener("click", () => this.set("sheets", "new", ""));
    tb.append(add); this.body.append(tb);
  }
  private history(d: any) {
    const undo: string[] = d.undo ?? [], redo: string[] = d.redo ?? [];
    this.body.append(h("div", { class: "phdr", text: `Undo (${undo.length})` }));
    this.list(undo.map((l, i) => ({ label: l, meta: String(i + 1), icon: "arrow.uturn.backward", current: i === undo.length - 1, tip: "Undo back to here", act: () => this.set("history", "undoTo", i + 1) })).reverse());
    if (redo.length) { this.body.append(h("div", { class: "phdr", text: `Redo (${redo.length})` })); this.list(redo.map((l) => ({ label: l, icon: "arrow.uturn.forward", act: () => this.app.redo() }))); }
    if (d.commands?.length) { this.body.append(h("div", { class: "phdr", text: "Command History" })); this.list(d.commands.slice(-50).reverse().map((c: string) => ({ label: c, icon: "terminal", act: () => this.app.runCommand(c) }))); }
    if (!undo.length && !redo.length) this.body.append(h("div", { class: "pempty", text: "Nothing to undo." }));
  }
  /** Panels the Mac builds in its UI layer: Browser (levels, sheets, 3D views), Tools, Selection, Alerts, Content, Navigator. */
  private localPanel(tab: string) {
    const app = this.app;
    if (tab === "Browser") {
      this.body.append(h("div", { class: "phdr", text: "Floor Plans" }));
      this.list([...(app.info?.levels ?? [])].sort((a, b) => b.elevation - a.elevation).map((l) => ({ label: l.name, meta: String(Math.round(l.elevation)), icon: "square", current: l.name === app.info?.currentLevel && app.mode !== "Sheet",
        act: () => this.set("levels", "current", l.name).then(() => app.setUI("mode", "2D")) })));
      this.body.append(h("div", { class: "phdr", text: "3D Views" }));
      this.list(["Front", "Aerial", "Corner"].map((n) => ({ label: n, icon: "cube", act: () => { app.setUI("mode", "3D"); app.runCommand(`CAMERA ${n}`); } })));
      this.body.append(h("div", { class: "phdr", text: "Sheets" }));
      this.list((app.info?.layouts ?? []).map((n, i) => ({ label: n, icon: "doc.richtext", current: app.mode === "Sheet" && app.activeLayout === i + 1, act: () => { app.activeLayout = i + 1; app.setUI("mode", "Sheet"); } })));
    } else if (tab === "Tools" || tab === "Content") {
      const groups: [string, [string, string, string][]][] = [
        ["Architecture", [["Wall", "rectangle.split.2x1", "WALL"], ["Door", "door.left.hand.open", "DOOR"], ["Window", "window.vertical.closed", "WINDOW"], ["Column", "cylinder", "COLUMN"], ["Slab", "square.3.layers.3d.bottom.filled", "SLAB"], ["Roof", "house", "ROOF"], ["Stair", "stairs", "STAIR"], ["Room", "square.dashed.inset.filled", "ROOM"]]],
        ["Furniture", [["Chair", "chair", "COMPONENT Chair"], ["Table", "table.furniture", "COMPONENT Table"], ["Sofa", "sofa", "COMPONENT Sofa"], ["Bed", "bed.double", "COMPONENT Bed"], ["Kitchen", "refrigerator", "COMPONENT Kitchen"], ["WC", "toilet", "COMPONENT WC"], ["Bath", "bathtub", "COMPONENT Bath"], ["Car", "car", "COMPONENT Car"]]],
        ["Drafting", [["Line", "line.diagonal", "LINE"], ["Polyline", "point.topleft.down.curvedto.point.bottomright.up", "PLINE"], ["Circle", "circle", "CIRCLE"], ["Rectangle", "rectangle", "RECTANG"], ["Hatch", "square.grid.3x3.fill", "HATCH"], ["Text", "textformat", "MTEXT"], ["Dimension", "ruler", "DIMLINEAR"]]],
      ];
      for (const [g, items] of groups) { this.body.append(h("div", { class: "phdr", text: g })); this.list(items.map(([l, sym, c]) => ({ label: l, icon: sym, act: () => app.runCommand(c), tip: c }))); }
    } else if (tab === "Selection") {
      const sel = app.selection;
      this.body.append(h("div", { class: "ptitle", text: sel.ids.length ? sel.summary : "No selection" }));
      if (sel.types?.length) this.list(sel.types.map((t) => ({ label: t.type, meta: String(t.count), icon: "info.square" })));
    } else if (tab === "Alerts") this.body.append(h("div", { class: "pempty", text: "No alerts." }));
    else this.body.append(h("div", { class: "pempty", text: "The navigator shows the model extents; use the wheel and middle button to navigate." }));
  }

  private set(panel: string, key: string, value: unknown, extra: Record<string, unknown> = {}) {
    return this.app.call("panel.set", { panel, key, value, ...extra }).then(() => this.app.refresh(["drawing", "properties", "layers", "document"])).catch(() => {});
  }

  private properties(d: any) {
    const app = this.app;
    const sel = app.selection.ids;
    if (!sel.length) {
      this.body.append(h("div", { class: "ptitle", text: "No selection" }), h("div", { class: "psub", text: "Click objects or drag a window to select. Properties of the selection appear here." }));
    } else {
      const head = h("div", { class: "prow", style: { paddingTop: "8px" } }, h("div", { class: "v", style: { fontWeight: "600" }, text: app.selection.summary || `${sel.length} selected` }));
      const clearBtn = h("button", { class: "iconbtn" }, icon("xmark.circle", 13)); help(clearBtn, "Clear selection");
      clearBtn.addEventListener("click", () => app.call("select.set", { ids: [] }).then(() => app.refresh(["selection"])));
      head.append(clearBtn);
      const tools = h("div", { class: "ptoolbar" });
      for (const [sym, tip, cmd] of [["line.3.horizontal.decrease.circle", "Quick Select…", "QSELECTDIALOG"], ["paintbrush.pointed", "Match properties from the first selected object (MATCHPROP)", "MATCHPROP"],
        ["square.on.square.intersection.dashed", "Select similar objects (SELECTSIMILAR)", "SELECTSIMILAR"], ["arrow.left.arrow.right.square", "Invert the selection (SELECTINVERT)", "SELECTINVERT"], ["scope", "Zoom to the selection", "ZOOM O"]]) {
        const b = h("button", { class: "iconbtn" }, icon(sym, 13)); help(b, tip); b.addEventListener("click", () => app.runCommand(cmd)); tools.append(b);
      }
      this.body.append(head, tools);
    }
    let sections: any[] = d?.sections ?? [];
    if (!d?.sections && d?.project && !sel.length) {
      const cap = (v: any) => (typeof v === "string" && v ? v[0].toUpperCase() + v.slice(1) : v);
      sections = [{ title: "Project", rows: ["name", "number", "client", "address", "author"].map((k) => ({ name: k[0].toUpperCase() + k.slice(1), value: d.project[k] ?? "", key: "project." + k, editable: true })) },
        { title: "Drawing", rows: [["Units", cap(d.drawing?.units)], ["Current layer", d.drawing?.currentLayer], ["Current level", d.drawing?.currentLevel], ["Objects", d.drawing?.objects], ["Building elements", d.drawing?.elements],
          ["Layers", d.drawing?.layers], ["Blocks", d.drawing?.blocks], ["File", d.drawing?.file ?? "—"]].map(([name, value]) => ({ name, value: value ?? "", readOnly: true })) }];
    } else if (!d?.sections && d?.rows) {
      const general = ["id", "type", "name", "layer", "color", "linetype", "lineweight", "material", "level"];
      const rows = (d.rows as any[]).filter((r) => !(sel.length > 1 && r.name === "id"));
      sections = [{ title: "General", rows: rows.filter((r) => general.includes(r.name)) }];
      const geo = rows.filter((r) => !general.includes(r.name));
      if (geo.length) sections.push({ title: "Geometry & Parameters", rows: geo });
      const opts: Record<string, string[]> = { layer: this.app.layers.layers.map((l: any) => l.name), level: (this.app.info?.levels ?? []).map((l) => String(l.id ?? l.name)) };
      for (const s2 of sections) for (const r of s2.rows) if (opts[r.name] && !r.readOnly && !r.options) r.options = opts[r.name];
    }
    for (const s of sections) {
      this.body.append(h("div", { class: "phdr", text: s.title }));
      for (const r0 of s.rows ?? []) {
        const r = Array.isArray(r0) ? { name: r0[0], value: r0[1] } : r0;
        const label = sel.length ? humanize(String(r.label ?? r.name)) : String(r.label ?? r.name);
        const row = h("div", { class: "prow" }, h("div", { class: "k", text: label }));
        const editable = (r.editable ?? (sel.length > 0 && !r.readOnly)) && !r.readOnly;
        if (editable && Array.isArray(r.options)) {
          const b = h("button", { class: "dropfield", style: { width: "100%" } }, h("span", { class: "t", text: String(r.value ?? "") }), icon("chevron.down", 10, 2));
          b.addEventListener("click", () => showMenu(r.options.map((o: string) => ({ title: o, checked: o === r.value, action: () => this.set("properties", r.key ?? r.name, o) })), b));
          row.append(h("div", { class: "v" }, b));
        } else if (editable) {
          const inp = h("input", { class: "pfield", value: String(r.value ?? "") }) as HTMLInputElement;
          const commit = () => { if (inp.value !== String(r.value ?? "")) this.set("properties", r.key ?? r.name, inp.value); };
          inp.addEventListener("keydown", (e) => { e.stopPropagation(); if (e.key === "Enter") { commit(); inp.blur(); } if (e.key === "Escape") { inp.value = String(r.value ?? ""); inp.blur(); } });
          inp.addEventListener("blur", commit);
          row.append(h("div", { class: "v" }, inp));
        } else row.append(h("div", { class: "v", text: String(r.value ?? "") }));
        this.body.append(row);
      }
    }
    if (sel.length > 1) this.body.append(h("div", { class: "psub", style: { padding: "10px" }, text: `Editing a field changes all ${sel.length} selected objects.` }));
  }

  private layers(d: any) {
    const app = this.app;
    const list: any[] = d?.layers ?? d?.items ?? app.layers.layers;
    const cur = list.find((l: any) => l.current)?.name ?? d?.current ?? app.sysvars.CLAYER ?? "0";
    const tb = h("div", { class: "ptoolbar" });
    for (const [sym, tip, act] of [["plus.circle", "New layer", () => this.set("layers", "new", "")], ["checkmark", "Make the selected layer current", () => {}],
      ["trash", "Delete the current layer", () => this.set("layers", "delete", cur)], ["rectangle.stack", "Layer States Manager (LAYERSTATE)", () => app.runCommand("LAYERSTATE")]] as [string, string, () => void][]) {
      const b = h("button", { class: "iconbtn" }, icon(sym, 13)); help(b, tip); b.addEventListener("click", act); tb.append(b);
    }
    this.body.append(tb, h("div", { class: "phdr", text: `Layers (${list.length})` }));
    const box = h("div", { class: "plist" });
    for (const l of list) {
      const isCur = l.name === cur;
      const row = h("div", { class: "li" + (isCur ? " cur" : "") });
      const cb = h("button", { class: "iconbtn" + (isCur ? " active" : "") }, isCur ? icon("checkmark", 12, 2) : h("span"));
      help(cb, "Make current"); cb.addEventListener("click", () => this.set("layers", "current", l.name).then(() => { app.sysvars.CLAYER = l.name; app.emit("sysvars"); }));
      const sw = h("span", { class: "swatch", style: { background: l.color ?? "#fff" } });
      const tog = (sym: string, off: string, key: string, on: boolean, tip: string) => {
        const b = h("button", { class: "iconbtn" }, icon(on ? sym : off, 12)); if (!on || key !== "on") b.style.color = key === "on" ? "var(--faint)" : on ? "var(--accent)" : "var(--dim)";
        help(b, tip); b.addEventListener("click", () => this.set("layers", `${l.name}.${key === "on" ? "visible" : key}`, !on)); return b;
      };
      row.append(cb, sw, h("span", { class: "name", text: l.name }), h("span", { class: "meta", text: String(l.count ?? l.objects ?? "") }),
        tog("eye", "eye.slash", "on", l.on !== false && l.visible !== false, l.on === false ? "Turn on" : "Turn off"),
        tog("snowflake", "sun.max", "frozen", !!l.frozen, l.frozen ? "Thaw" : "Freeze"),
        tog("lock", "lock.open", "locked", !!l.locked, l.locked ? "Unlock" : "Lock"));
      box.append(row);
    }
    this.body.append(box);
  }

  private levels(d: any) {
    const app = this.app;
    const list: any[] = [...(d?.levels ?? app.info?.levels ?? [])].sort((a, b) => b.elevation - a.elevation);
    const cur = list.find((l: any) => l.current)?.name ?? d?.current ?? app.info?.currentLevel;
    const tb = h("div", { class: "ptoolbar" });
    for (const [sym, tip, cmd] of [["plus.circle", "New level", "new"], ["trash", "Delete the current level", "delete"]]) {
      const b = h("button", { class: "iconbtn" }, icon(sym, 13)); help(b, tip); b.addEventListener("click", () => this.set("levels", cmd, cmd === "delete" ? cur : "")); tb.append(b);
    }
    this.body.append(tb, h("div", { class: "phdr", text: "Levels" }));
    const box = h("div", { class: "plist" });
    for (const l of list) {
      const row = h("div", { class: "li" + (l.name === cur ? " cur" : "") }, icon("building.2", 12), h("span", { class: "name", text: l.name }),
        h("span", { class: "meta", text: `${Math.round(l.elevation)}  ·  h ${Math.round(l.height ?? 0)}${l.elements !== undefined ? `  ·  ${l.elements}` : ""}` }));
      row.addEventListener("click", () => this.set("levels", "current", l.name));
      box.append(row);
    }
    this.body.append(box);
  }

  private materials(d: any) {
    const items: any[] = d.items ?? d.materials ?? [];
    this.body.append(h("div", { class: "phdr", text: `Materials (${items.length})` }));
    const g = h("div", { class: "matgrid" });
    for (const m of items) {
      const cell = h("div", { class: "m" }, h("div", { class: "ball", style: { background: m.color ?? "#888", opacity: String(1 - (m.transparency ?? 0) * 0.6) } }), h("span", { text: m.label ?? m.name }));
      cell.addEventListener("click", () => this.app.selection.ids.length ? this.set("properties", "material", m.name) : this.app.print(`Select objects, then click ${m.name} to apply it.`));
      help(cell, `Apply ${m.label ?? m.name} to the selection`);
      g.append(cell);
    }
    this.body.append(g);
  }

  private generic(tab: string, d: any) {
    const sections: any[] = d.sections ?? [{ title: d.title ?? tab, items: d.items ?? [], rows: d.rows }];
    for (const s of sections) {
      if (s.title) this.body.append(h("div", { class: "phdr", text: s.title }));
      for (const r of s.rows ?? []) this.body.append(h("div", { class: "prow" }, h("div", { class: "k", text: String(r.name ?? r[0]) }), h("div", { class: "v", text: String(r.value ?? r[1] ?? "") })));
      const box = h("div", { class: "plist" });
      for (const it of s.items ?? []) {
        const row = h("div", { class: "li" + (it.active ? " cur" : "") },
          it.color ? h("span", { class: "swatch", style: { background: it.color } }) : it.icon ? icon(it.icon, 12) : null,
          h("span", { class: "name", text: String(it.label ?? it.name ?? it) }), it.detail ? h("span", { class: "meta", text: String(it.detail) }) : null);
        row.addEventListener("click", () => it.command ? this.app.runCommand(it.command) : this.set(tab.toLowerCase(), "activate", it.id ?? it.label));
        box.append(row);
      }
      this.body.append(box);
    }
    if (!sections.some((s) => (s.items ?? []).length || (s.rows ?? []).length)) this.body.append(h("div", { class: "pempty", text: "Nothing here yet." }));
  }
}
