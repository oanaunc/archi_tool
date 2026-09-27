// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Layer Properties Manager: the Layers panel of the Mac app (LayersPanel, LayerRow, LayerGroupRow in
// ArchiApp/PanelsView.swift and AppNavigationViews.swift): New / Delete / Current, flat list or layer tree grouped by
// name prefix with bulk toggles, Layer States Manager, the filter field and menu (on and thawed / used / unlocked,
// saved filters kept in the drawing), columns current · on · freeze · lock · colour · name · linetype · lineweight ·
// transparency · plot, inline rename and the Description… context item. Every edit is one undo step in the engine.
import { h, clear } from "../dom";
import { icon } from "../icons";
import { showMenu, help, MenuItem } from "../ui/menu";
import { iconButton, flatButton, promptDialog } from "./ui";
import { app } from "./context";
import { openLayerStates } from "./layerstates";

export const STANDARD_LINEWEIGHTS = [0, 0.05, 0.09, 0.13, 0.15, 0.18, 0.2, 0.25, 0.3, 0.35, 0.4, 0.5, 0.53, 0.6, 0.7, 0.8, 0.9, 1, 1.06, 1.2, 1.4, 1.58, 2, 2.11];
/** basicColors (Theme.swift) as their ACI colours (aciColor in ArchiCore/Model/Entity.swift). */
export const BASIC_COLORS: [string, string][] = [["Red", "#FF0000"], ["Yellow", "#FFFF00"], ["Green", "#00FF00"], ["Cyan", "#00FFFF"], ["Blue", "#0000FF"],
  ["Magenta", "#FF00FF"], ["White", "#FFFFFF"], ["Gray", "#808080"], ["Light Gray", "#BFBFBF"], ["Orange", "#FF8000"], ["Brown", "#994D00"]];

/** LayerFilter: "#on #used #unlocked" flags then name wildcards (A-*, ~*TEXT*, comma-separated; a bare word is a substring). */
export class LayerFilter {
  pattern = ""; onlyVisible = false; onlyUsed = false; onlyUnlocked = false;
  constructor(stored = "") {
    const rest: string[] = [];
    for (const t of stored.split(" ").filter(Boolean)) {
      const l = t.toLowerCase();
      if (l === "#on") this.onlyVisible = true; else if (l === "#used") this.onlyUsed = true; else if (l === "#unlocked") this.onlyUnlocked = true; else rest.push(t);
    }
    this.pattern = rest.join(" ");
  }
  get stored() { return [...(this.onlyVisible ? ["#on"] : []), ...(this.onlyUsed ? ["#used"] : []), ...(this.onlyUnlocked ? ["#unlocked"] : []), this.pattern].join(" "); }
  get isEmpty() { return !this.pattern.trim() && !this.onlyVisible && !this.onlyUsed && !this.onlyUnlocked; }
  static wildcard(pattern: string, text: string): boolean {
    let re = "";
    for (const c of pattern.toLowerCase()) re += c === "*" ? ".*" : c === "?" ? "." : c === "#" ? "\\d" : c === "@" ? "\\p{L}" : c.replace(/[.+^${}()|[\]\\]/g, "\\$&");
    return new RegExp(`^${re}$`, "u").test(text.toLowerCase());
  }
  static matchesPattern(pattern: string, name: string): boolean {
    const items = pattern.split(",").map((x) => x.trim()).filter(Boolean);
    if (!items.length) return true;
    const m = (item: string) => (/[*?#@]/.test(item) ? LayerFilter.wildcard(item, name) : name.toLowerCase().includes(item.toLowerCase()));
    const neg = items.filter((x) => x.startsWith("~")).map((x) => x.slice(1)), pos = items.filter((x) => !x.startsWith("~"));
    if (neg.some(m)) return false;
    return !pos.length || pos.some(m);
  }
  matches(l: { name: string; visible: boolean; frozen: boolean; locked: boolean }, used: boolean) {
    if (this.onlyVisible && (!l.visible || l.frozen)) return false;
    if (this.onlyUnlocked && l.locked) return false;
    if (this.onlyUsed && !used) return false;
    return LayerFilter.matchesPattern(this.pattern, l.name);
  }
}

/** LayerTree.key: "xref|", the prefix before -, _ or space, "(Standard)" for 0 and DEFPOINTS. */
export function layerGroupKey(n: string): string {
  const bar = n.indexOf("|");
  if (bar >= 0) return n.slice(0, bar + 1);
  const m = n.search(/[-_ ]/);
  if (m > 0) return n.slice(0, m);
  return n === "0" || n.toUpperCase() === "DEFPOINTS" ? "(Standard)" : n;
}

// Panel state kept across refreshes (the SwiftUI @State / @AppStorage of LayersPanel).
const state = { selected: null as string | null, filter: new LayerFilter(), savedFilterName: null as string | null, closedGroups: new Set<string>(), filterFocus: false };
function treeView(): boolean { try { return localStorage.getItem("archi.layerTreeView") === "true"; } catch { return false; } }
function setTreeView(v: boolean) { try { localStorage.setItem("archi.layerTreeView", String(v)); } catch {} }

/** LAYERFILTER Apply / Clear (host action "layerFilter"): sets the panel filter. */
export function requestLayerFilter(stored: string) { state.filter = new LayerFilter(stored); state.savedFilterName = null; }

type SetFn = (key: string, value: unknown) => Promise<unknown>;

export function renderLayersPanel(body: HTMLElement, d: any, set: SetFn) {
  const a = app();
  const all: any[] = d?.layers ?? a.layers.layers ?? [];
  const linetypes: string[] = d?.linetypes ?? ["Continuous"];
  const current: string = d?.current ?? a.sysvars.CLAYER ?? "0";
  const f = state.filter;
  const layers = all.filter((l) => f.matches({ name: l.name, visible: l.visible !== false, frozen: !!l.frozen, locked: !!l.locked }, (l.count ?? 0) > 0));
  const sel = all.find((l) => l.name === state.selected);
  const deletable = () => { const s = all.find((l) => l.name === state.selected); return s && s.name !== "0" && s.name.toLowerCase() !== current.toLowerCase() && (s.count ?? 0) === 0 ? s : null; };
  const canDelete = !!deletable();
  const tree = treeView();
  const root = h("div", { class: "lp" });

  const tools = h("div", { class: "lp-tools" },
    flatButton("New", async () => { const before = new Set(all.map((l) => l.name)); await set("new", ""); state.selected = a.layers.layers.map((l: any) => l.name).find((n: string) => !before.has(n)) ?? state.selected; a.emit("panel"); }, { compact: true, symbol: "plus", help: "New layer" }),
    flatButton("Delete", () => { const s = deletable(); if (s) { state.selected = null; void set("delete", s.name); } }, { compact: true, symbol: "minus", disabled: !canDelete, help: "Delete the selected layer (must be empty, not 0 or current)" }),
    flatButton("Current", () => { if (state.selected) void setCurrent(state.selected); }, { compact: true, symbol: "checkmark.circle", disabled: !sel, help: "Make the selected layer current" }),
    h("span", { class: "spacer" }),
    iconButton(tree ? "list.bullet.indent" : "list.bullet", tree ? "Flat layer list" : "Layer tree grouped by name prefix (A-, S-, xref|)", () => { setTreeView(!tree); a.emit("panel"); }),
    iconButton("rectangle.stack", "Layer States Manager (LAYERSTATE)", () => void openLayerStates()));
  const setCurrent = (n: string) => set("current", n).then(() => { a.sysvars.CLAYER = n; a.emit("sysvars"); });

  // Filter field and menu.
  const field = h("input", { class: "darkfield", placeholder: "Filter: name, A-*, ~*TEXT*", spellcheck: false }) as HTMLInputElement;
  field.value = f.pattern;
  field.addEventListener("input", () => { f.pattern = field.value; state.filterFocus = true; a.emit("panel"); });
  field.addEventListener("blur", () => { state.filterFocus = false; });
  field.addEventListener("keydown", (e) => e.stopPropagation());
  const fbtn = h("button", { class: "iconbtn" + (f.isEmpty ? "" : " on") }, icon(f.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill", 13));
  help(fbtn, "Layer filters (saved with the drawing)");
  fbtn.addEventListener("click", async () => {
    const saved: { name: string; filter: string }[] = (await a.tryCall("layerfilter.list", {}))?.filters ?? [];
    const items: MenuItem[] = [
      { title: "On and thawed only", checked: f.onlyVisible, action: () => { f.onlyVisible = !f.onlyVisible; a.emit("panel"); } },
      { title: "Used layers only", checked: f.onlyUsed, action: () => { f.onlyUsed = !f.onlyUsed; a.emit("panel"); } },
      { title: "Unlocked only", checked: f.onlyUnlocked, action: () => { f.onlyUnlocked = !f.onlyUnlocked; a.emit("panel"); } },
      { separator: true },
    ];
    if (saved.length) {
      items.push({ header: "Saved filters" });
      for (const s of saved) items.push({ title: s.name, checked: state.savedFilterName === s.name, action: () => { state.filter = new LayerFilter(s.filter); state.savedFilterName = s.name; a.emit("panel"); } });
    }
    items.push({ title: "Save Filter…", disabled: f.isEmpty, action: () => void saveFilter(saved.length) });
    if (state.savedFilterName) { const n = state.savedFilterName; items.push({ title: `Delete Filter ${n}`, action: async () => { await a.tryCall("layerfilter.delete", { name: n }); state.savedFilterName = null; a.emit("panel"); } }); }
    items.push({ title: "Clear Filter", disabled: f.isEmpty, action: () => { state.filter = new LayerFilter(); state.savedFilterName = null; a.emit("panel"); } });
    showMenu(items, fbtn);
  });
  const saveFilter = async (count: number) => {
    const n = await promptDialog("Save Layer Filter", `Name for the filter “${f.stored.trim()}”:`, state.savedFilterName ?? `Filter ${count + 1}`, "Save");
    const name = (n ?? "").trim().toUpperCase();
    if (!name) return;
    await a.tryCall("layerfilter.save", { name, filter: f.stored });
    state.savedFilterName = name;
    a.emit("panel");
  };

  const head = h("div", { class: "lp-head" }, h("span"), icon("eye", 11), icon("snowflake", 11), icon("lock", 11), icon("paintpalette", 11),
    h("span", { class: "nm", text: "Name" }), h("span", { class: "lt", text: "Linetype" }), h("span", { class: "lw", text: "LW" }), h("span", { class: "tp", text: "T%" }), icon("printer", 11));
  const list = h("div", { class: "lp-list" });

  const row = (l: any, indent = false) => {
    const isCur = l.name.toLowerCase() === current.toLowerCase();
    const r = h("div", { class: "lp-row" + (state.selected === l.name ? " sel" : "") });
    if (indent) r.style.paddingLeft = "18px";
    const edit = (field: string, value: unknown) => set(`${l.name}.${field}`, value);
    const cur = h("button", { class: "cur" + (isCur ? " on" : "") }, icon(isCur ? "checkmark.circle.fill" : "circle", 12, 1.8));
    help(cur, isCur ? "Current layer" : "Make current");
    cur.addEventListener("click", (e) => { e.stopPropagation(); void setCurrent(l.name); });
    const tog = (on: boolean, symOn: string, symOff: string, tip: string, fieldName: string, value: boolean) => {
      const b = h("button", { class: "tg" + (on ? "" : " off") }, icon(on ? symOn : symOff, 11));
      help(b, tip); b.addEventListener("click", (e) => { e.stopPropagation(); void edit(fieldName, value); }); return b;
    };
    const visible = l.visible !== false, frozen = !!l.frozen, locked = !!l.locked, plot = l.plot !== false;
    const sw = h("button", { class: "c16" }, h("span", { class: "sw", style: { background: l.color ?? "#FFFFFF" } }));
    help(sw, `Layer color ${String(l.color ?? "").toUpperCase()}`);
    sw.addEventListener("click", (e) => {
      e.stopPropagation();
      showMenu([...BASIC_COLORS.map(([n, c]) => ({ title: n, swatch: c, action: () => void edit("color", c) })), { separator: true },
        { title: "More Colors…", action: () => { const i = h("input", { type: "color", value: /^#[0-9a-f]{6}$/i.test(l.color) ? l.color : "#ffffff" }) as HTMLInputElement; i.addEventListener("change", () => void edit("color", i.value.toUpperCase())); i.click(); } }], sw);
    });
    const name = h("span", { class: "nm" });
    if (l.name === "0") name.append(h("span", { text: l.name }));
    else {
      const inp = h("input", { value: l.name, spellcheck: false }) as HTMLInputElement;
      const commit = () => { const v = inp.value.trim(); if (v && v !== l.name) { if (state.selected === l.name) state.selected = v; void set(`${l.name}.name`, v); } else inp.value = l.name; };
      inp.addEventListener("keydown", (e) => { e.stopPropagation(); if (e.key === "Enter") { inp.blur(); } else if (e.key === "Escape") { inp.value = l.name; inp.blur(); } });
      inp.addEventListener("blur", commit);
      inp.addEventListener("focus", () => { state.selected = l.name; r.parentElement?.querySelectorAll(".lp-row.sel").forEach((x) => x.classList.remove("sel")); r.classList.add("sel"); });
      name.append(inp);
    }
    const menuBtn = (cls: string, text: string, items: () => MenuItem[], tip?: string) => {
      const b = h("button", { class: "mb " + cls, text }); if (tip) help(b, tip);
      b.addEventListener("click", (e) => { e.stopPropagation(); showMenu(items(), b); }); return b;
    };
    const t = Number(l.transparency ?? 0), tpct = Math.round(t > 1 ? t : t * 100);
    r.append(cur,
      tog(visible, "eye", "eye.slash", visible ? "On — click to turn off" : "Off — click to turn on", "visible", !visible),
      tog(!frozen, "sun.max", "snowflake", frozen ? "Frozen — click to thaw" : "Thawed — click to freeze", "frozen", !frozen),
      tog(!locked, "lock.open", "lock.fill", locked ? "Locked — click to unlock" : "Unlocked — click to lock", "locked", !locked),
      sw, name,
      menuBtn("lt", l.linetype ?? "Continuous", () => linetypes.map((n) => ({ title: n, checked: n === l.linetype, action: () => void edit("linetype", n) }))),
      menuBtn("lw", Number(l.lineweight ?? 0).toFixed(2), () => STANDARD_LINEWEIGHTS.map((w) => ({ title: `${w.toFixed(2)} mm`, checked: Math.abs(w - Number(l.lineweight)) < 1e-6, action: () => void edit("lineweight", w) }))),
      menuBtn("tp", String(tpct), () => [0, 10, 25, 50, 75, 90].map((p) => ({ title: `${p} %`, checked: p === tpct, action: () => void edit("transparency", p / 100) })), "Layer transparency %"),
      tog(plot, "printer", "printer.dotmatrix", plot ? "Plots — click to not plot" : "Does not plot — click to plot", "plot", !plot));
    help(r, `${l.name} — ${l.count ?? 0} object(s)${l.description ? " — " + l.description : ""}`);
    r.addEventListener("click", () => { state.selected = l.name; list.querySelectorAll(".lp-row.sel").forEach((x) => x.classList.remove("sel")); r.classList.add("sel"); refreshTools(); });
    r.addEventListener("dblclick", (e) => { if (!(e.target as HTMLElement).closest("input,button")) void setCurrent(l.name); });
    r.addEventListener("contextmenu", (e) => {
      e.preventDefault();
      showMenu([{ title: "Description…", action: async () => { const v = await promptDialog(`Layer ${l.name} — description`, "", l.description ?? "", "OK"); if (v !== null) void edit("description", v); } }], { x: e.clientX, y: e.clientY });
    });
    return r;
  };

  if (tree) {
    const order: string[] = [], groups = new Map<string, string[]>();
    for (const l of layers) { const k = layerGroupKey(l.name); if (!groups.has(k)) { groups.set(k, []); order.push(k); } groups.get(k)!.push(l.name); }
    for (const g of order) {
      const members = all.filter((l) => groups.get(g)!.includes(l.name));
      const allOn = members.every((l) => l.visible !== false), allThawed = members.every((l) => !l.frozen), allUnlocked = members.every((l) => !l.locked);
      const open = !state.closedGroups.has(g);
      const bulk = (sym: string, tip: string, key: string, value: boolean) => {
        const b = h("button", { class: "tg" }, icon(sym, 11)); help(b, tip);
        b.addEventListener("click", async () => { await a.tryCall("layers.group", { group: g, key, value }); await a.refresh(["layers", "drawing", "document"]); }); return b;
      };
      const fold = h("button", { class: "tg fold" }, icon(open ? "chevron.down" : "chevron.right", 9, 2.4));
      fold.addEventListener("click", () => { if (open) state.closedGroups.add(g); else state.closedGroups.delete(g); a.emit("panel"); });
      list.append(h("div", { class: "lp-group" }, fold,
        bulk(allOn ? "eye" : "eye.slash", allOn ? "Turn the group off" : "Turn the group on", "visible", !allOn),
        bulk(allThawed ? "sun.max" : "snowflake", allThawed ? "Freeze the group" : "Thaw the group", "frozen", allThawed),
        bulk(allUnlocked ? "lock.open" : "lock.fill", allUnlocked ? "Lock the group" : "Unlock the group", "locked", allUnlocked),
        h("span", { class: "tg", style: { color: "var(--dim)" } }, icon("folder", 10)), h("span", { class: "gname", text: `${g}  (${groups.get(g)!.length})` })));
      if (open) for (const l of layers.filter((x) => groups.get(g)!.includes(x.name))) list.append(row(l, true));
    }
  } else for (const l of layers) list.append(row(l));

  const foot = h("div", { class: "lp-foot" + (f.isEmpty ? "" : " accent"), text: f.isEmpty ? `${all.length} layers · double-click the radio to make current` : `${layers.length} of ${all.length} layers match the filter` });
  root.append(tools, h("div", { class: "lp-filter" }, field, fbtn), head, list, foot);
  clear(body);
  body.append(root);
  if (state.filterFocus) { field.focus(); field.setSelectionRange(field.value.length, field.value.length); }
  function refreshTools() {
    (tools.children[1] as HTMLButtonElement).disabled = !deletable();
    (tools.children[2] as HTMLButtonElement).disabled = !state.selected;
  }
}
