// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Fixture-engine side of the dialog methods (docs/ENGINE-PROTOCOL.md "Dialogs"): recorded answers when the fixtures
// have them, otherwise a small stateful simulation, so the dialogs can be exercised in the browser test page. The
// portable UI commands (OPTIONS, QSELECTDIALOG, LAYERSTATE, PAGESETUP, CUI …) answer with their `host` notification.
// Never used inside the Electron app.

const UI_COMMANDS: { name: string; aliases: string[]; category: string; summary: string }[] = [
  { name: "CLEANSCREENOFF", aliases: ["RIBBON", "RB"], category: "View", summary: "Restore and expand the ribbon." },
  { name: "OPTIONS", aliases: ["OP", "PREFERENCES", "SETTINGS", "CONFIG"], category: "Settings", summary: "Opens Settings: units, grid and snaps, autosave, colors, shortcuts, toolbar, agents." },
  { name: "AGENTSETTINGS", aliases: ["AGENTS", "AGENTSERVER"], category: "Scripting", summary: "Agent server settings: port, start/stop, token, auto-start." },
  { name: "CURSORSIZE", aliases: [], category: "Settings", summary: "Sets the crosshair size as a percentage of the view (1–100)." },
  { name: "SAVETIME", aliases: ["AUTOSAVE"], category: "Settings", summary: "Sets the autosave interval in minutes (0 turns autosave off)." },
  { name: "THEME", aliases: ["COLORTHEME", "APPEARANCE"], category: "Settings", summary: "Switches the interface theme [Dark/Light]." },
  { name: "QSELECTDIALOG", aliases: ["QSD", "QUICKSELECT"], category: "Select", summary: "Quick Select dialog: type, property, operator and value with a live match count." },
  { name: "LAYERSTATE", aliases: ["LAS", "LMAN", "-LAYERSTATE"], category: "Layers", summary: "Layer states: Dialog, or ?/Save/Restore/Delete/Import/Export/Rename on the command line (saved in the drawing)." },
  { name: "LAYERFILTER", aliases: ["LFILTER"], category: "Layers", summary: "Filters the Layers panel (A-*, ~*TEXT*, #on #used); Save/Delete/List named filters kept in the drawing." },
  { name: "WSCURRENT", aliases: ["WS", "WORKSPACE"], category: "View", summary: "Switches workspace (panels, views and ribbon tab), e.g. WSCURRENT 3D Modeling." },
  { name: "WSSAVE", aliases: [], category: "View", summary: "Saves the current window arrangement as a named workspace." },
  { name: "CUI", aliases: ["CUSTOMIZE", "RIBBONCUSTOMIZE", "-CUI"], category: "Settings", summary: "Customizes the ribbon: Dialog, Add a panel of commands to a tab, Remove, Hide/Show a built-in panel, List, Export/Import a customisation file, Reset." },
  { name: "PAGESETUP", aliases: ["PSETUP", "PAGESETUPMANAGER"], category: "Output", summary: "Page setup of the active sheet or model: paper, plot style, lineweights, plot stamp, scale." },
  { name: "NEWFROMTEMPLATE", aliases: ["NEWTEMPLATE", "QNEW"], category: "File", summary: "Starts a new drawing from a template (built-in or from the templates folder)." },
  { name: "SAVEASTEMPLATE", aliases: ["SAVETEMPLATE", "TEMPLATESAVE"], category: "File", summary: "Saves the drawing's settings, layers, styles and content as a template in the templates folder." },
  { name: "UNITS", aliases: ["UN", "-UNITS"], category: "Settings", summary: "Sets drawing units (mm, cm, m, in, ft) and optionally scales the drawing." },
  { name: "DSETTINGS", aliases: ["DS", "SE", "DDRMODES"], category: "Settings", summary: "Opens the drafting settings (snap, grid, polar, object snap)." },
];
const SNAP_KINDS = ["endpoint", "midpoint", "center", "node", "quadrant", "intersection", "extension", "insertion", "perpendicular", "tangent", "nearest", "parallel", "grid"];
const LIN = ["Scientific", "Decimal", "Engineering", "Architectural", "Fractional"];
const ANG = ["Decimal degrees", "Deg/Min/Sec", "Grads", "Radians", "Surveyor's units"];
const UNITS: [string, string, number][] = [["millimeters", "mm", 1], ["centimeters", "cm", 10], ["meters", "m", 1000], ["inches", "in", 25.4], ["feet", "ft", 304.8]];
const PAPERS: [string, number, number][] = [["A4", 297, 210], ["A3", 420, 297], ["A2", 594, 420], ["A1", 841, 594], ["A0", 1189, 841], ["Letter", 279.4, 215.9], ["Tabloid", 431.8, 279.4], ["ARCH D", 914.4, 609.6],
  ["ANSI A", 279.4, 215.9], ["ANSI B", 431.8, 279.4], ["ANSI C", 558.8, 431.8], ["ANSI D", 863.6, 558.8], ["ANSI E", 1117.6, 863.6], ["ARCH A", 304.8, 228.6], ["ARCH B", 457.2, 304.8], ["ARCH C", 609.6, 457.2], ["ARCH E1", 1066.8, 762], ["ARCH E", 1219.2, 914.4]];

interface FakeState {
  units: { units: string; lunits: number; luprec: number; aunits: number; auprec: number };
  drafting: any; states: Map<string, { layers: Record<string, any>; date: string }>; filters: Map<string, string>;
  pageSetups: Map<string, any>; uiPrefs: Record<string, string>; templates: string[];
}
const st: FakeState = {
  units: { units: "millimeters", lunits: 2, luprec: 2, aunits: 0, auprec: 0 },
  drafting: { showGrid: true, gridSnap: false, gridSpacing: 100, ortho: false, polarTracking: true, polarIncrement: 45, dynamicInput: true, lineweightDisplay: true, textHeight: 250, wallThickness: 200, wallHeight: 3000, objectSnap: true, snapModes: ["endpoint", "midpoint", "center", "node", "quadrant", "intersection", "insertion", "perpendicular"] },
  states: new Map(), filters: new Map(), pageSetups: new Map(), uiPrefs: {}, templates: [],
};

function unitsInfo(u = st.units) {
  const frac = u.lunits === 4 || u.lunits === 5;
  const mm = UNITS.find((x) => x[0] === u.units)?.[2] ?? 1, ab = UNITS.find((x) => x[0] === u.units)?.[1] ?? "mm";
  const v = 42.5 / (u.units === "inches" ? 1 : u.units === "feet" ? 12 : mm / 25.4);
  return {
    ...u, unitList: UNITS.map(([value, a]) => ({ value, title: `${value[0].toUpperCase() + value.slice(1)} (${a})`, abbreviation: a })),
    linearTypes: LIN.map((title, i) => ({ value: i + 1, title })), angularTypes: ANG.map((title, value) => ({ value, title })),
    linearPrecisionLabel: "Precision: " + (frac ? `1/${1 << u.luprec}"` : `${u.luprec} decimals`), angularPrecisionLabel: `Precision: ${u.auprec}`,
    sample: `Sample: ${linear(v * (u.units === "inches" ? 1 : u.units === "feet" ? 12 : mm / 25.4), v, u.lunits, u.luprec)}  ·  ${(45).toFixed(u.auprec)}°`,
    note: `Coordinates are stored as drawing units. Changing the unit relabels the drawing and affects exports (1 ${ab} = ${mm} mm); it does not rescale existing geometry. Use SCALE to resize objects.`,
  };
}
/** UnitFormat.linear (decimal, scientific, engineering, architectural, fractional) for the sample text. */
function linear(inches: number, v: number, type: number, p: number): string {
  if (type === 1) return v.toExponential(p).toUpperCase().replace(/E([+-])(\d)$/, "E$10$2");
  if (type === 2) return v.toFixed(p);
  const sign = inches < 0 ? "-" : "", a = Math.abs(inches);
  if (type === 3) { let ft = Math.floor(a / 12), inch = a - ft * 12; if (Number(inch.toFixed(p)) >= 12) { ft += 1; inch = 0; } return `${sign}${ft}'-${inch.toFixed(p)}"`; }
  const den = 1 << p;
  let whole = Math.floor(a), num = Math.round((a - whole) * den), d = den;
  if (num === den) { whole += 1; num = 0; }
  while (num > 0 && num % 2 === 0 && d > 1) { num /= 2; d /= 2; }
  const frac = num === 0 ? "" : `${num}/${d}`;
  if (type === 5) return sign + (frac ? (whole === 0 ? frac : `${whole} ${frac}`) : `${whole}`) + '"';
  const ft = Math.floor(whole / 12), inch = whole % 12;
  return `${sign}${ft}'-${frac ? (inch === 0 ? frac : `${inch} ${frac}`) : inch}"`;
}
function draftingInfo() { return { ...st.drafting, snapKinds: SNAP_KINDS, polarIncrements: [5, 10, 15, 18, 22.5, 30, 45, 90], units: "mm" }; }
function statesList() { return [...st.states.entries()].sort((a, b) => a[0].localeCompare(b[0])).map(([name, s]) => ({ name, layers: Object.keys(s.layers).length, date: s.date, description: "", currentLayer: null })); }

export function fakeDialogCall(fe: any, method: string, p: any): any {
  const emitHost = (params: any) => fe.emit("host", params);
  switch (method) {
    case "engine.hello": {
      const h = fe.hello;
      if (h && Array.isArray(h.commands)) for (const c of UI_COMMANDS) if (!h.commands.some((x: any) => x.name === c.name)) h.commands.push({ ...c, modifies: false });
      return undefined;
    }
    case "command.run": {
      const toks = String(p.line ?? "").trim().split(/\s+/);
      const name = toks[0]?.toUpperCase() ?? "";
      const def = UI_COMMANDS.find((c) => c.name === name || c.aliases.includes(name));
      if (!def || def.name === "UNITS" || def.name === "DSETTINGS") {
        if (def?.name === "UNITS") { fe.log("Command: UNITS"); emitHost({ action: "showPanel", panel: "Units" }); return idle(); }
        if (def?.name === "DSETTINGS") { fe.log("Command: DSETTINGS"); emitHost({ action: "showPanel", panel: "Drafting Settings" }); return idle(); }
        return undefined;
      }
      fe.log(`Command: ${toks[0].toUpperCase()}`);
      const arg = toks.slice(1).join(" ");
      switch (def.name) {
        case "CLEANSCREENOFF": emitHost({ action: "cleanScreen", on: false }); emitHost({ action: "ribbonExpand" }); break;
        case "OPTIONS": emitHost({ action: "dialog", dialog: "options", tab: arg || "General" }); break;
        case "AGENTSETTINGS": emitHost({ action: "dialog", dialog: "options", tab: "Agents" }); break;
        case "QSELECTDIALOG": emitHost({ action: "dialog", dialog: "quickSelect" }); break;
        case "LAYERSTATE": emitHost({ action: "dialog", dialog: "layerStates" }); break;
        case "PAGESETUP": emitHost({ action: "dialog", dialog: "pageSetup" }); break;
        case "CUI": if (!arg || /^d/i.test(arg)) emitHost({ action: "dialog", dialog: "cui" }); break;
        case "CURSORSIZE": { const v = Number(arg); if (Number.isInteger(v) && v >= 1 && v <= 100) emitHost({ action: "preference", key: "cursorSize", value: v }); else fe.log("Requires an integer between 1 and 100."); break; }
        case "THEME": emitHost({ action: "preference", key: "theme", value: /^l/i.test(arg) ? "light" : "dark" }); fe.log(`${/^l/i.test(arg) ? "Light" : "Dark"} theme.`); break;
        case "WSCURRENT": if (arg) { emitHost({ action: "workspace", name: arg }); fe.log(`Workspace: ${arg}`); } break;
        case "WSSAVE": if (arg) { emitHost({ action: "workspaceSave", name: arg }); fe.log(`Workspace "${arg}" saved.`); } break;
        case "LAYERFILTER": emitHost({ action: "layerFilter", filter: arg.replace(/^(apply|clear)\s*/i, "") }); break;
        default: fe.log(`${def.name} runs in archi-engine.`);
      }
      return idle();
    }
    case "ui.prefs": Object.assign(st.uiPrefs, p.values ?? {}); return { ...st.uiPrefs };
    case "units.get": return unitsInfo({ ...st.units, ...pick(p, ["units", "lunits", "luprec", "aunits", "auprec"]) });
    case "units.set": {
      const next = { ...st.units, ...pick(p, ["units", "lunits", "luprec", "aunits", "auprec"]) };
      if (JSON.stringify(next) !== JSON.stringify(st.units)) {
        st.units = next;
        fe.info.units = next.units; fe.info.unitAbbreviation = UNITS.find((x) => x[0] === next.units)?.[1];
        fe.snapshot?.("Units"); fe.changed?.("document");
      }
      return unitsInfo();
    }
    case "drafting.get": return draftingInfo();
    case "drafting.set": for (const k of Object.keys(st.drafting)) if (p[k] !== undefined) st.drafting[k] = p[k]; syncVars(fe); return draftingInfo();
    case "drafting.defaults": {
      const d = p.draft ?? {};
      for (const k of ["showGrid", "gridSnap", "ortho", "polarIncrement", "objectSnap", "snapModes", "dynamicInput", "lineweightDisplay", "gridSpacing"]) if (d[k] !== undefined) st.drafting[k] = d[k];
      if (d.polarTracking !== undefined) st.drafting.polarTracking = d.polarTracking && !st.drafting.ortho;
      if (p.units) { st.units.units = p.units; fe.info.units = p.units; }
      syncVars(fe);
      return draftingInfo();
    }
    case "qselect.options": {
      const types = new Set<string>();
      for (const r of fe.raw ?? []) if (r.id) types.add(typeOf(fe, r));
      return {
        types: [{ value: "*", title: "Multiple (all types)" }, ...[...types].sort().map((t) => ({ value: t, title: t[0].toUpperCase() + t.slice(1) }))],
        properties: ["*", "layer", "color", "linetype", "lineweight", "length", "area", "radius", "height", "contents", "name", "material", "level", "x", "y"].map((v) => ({ value: v, title: v === "*" ? "None (type only)" : v[0].toUpperCase() + v.slice(1) })),
        operators: [["=", "= Equals"], ["!=", "≠ Not equal"], [">", "> Greater than"], ["<", "< Less than"], [">=", "≥ Greater or equal"], ["<=", "≤ Less or equal"]].map(([value, title]) => ({ value, title })),
        layers: (fe.layers?.layers ?? []).map((l: any) => l.name), selectionCount: fe.selection?.size ?? 0, scope: 0,
      };
    }
    case "qselect.run": {
      const cands: any[] = p.scope === 1 ? (fe.raw ?? []).filter((r: any) => r.id && fe.selection.has(r.id)) : (fe.raw ?? []).filter((r: any) => r.id);
      let ids = cands.filter((r) => !p.type || p.type === "*" || typeOf(fe, r) === String(p.type).toLowerCase());
      if (p.property === "layer" && p.value) ids = ids.filter((r) => (r.layer ?? "0").toLowerCase() === String(p.value).toLowerCase());
      const out: any = { count: ids.length };
      if (p.apply) {
        const s: Set<string> = fe.selection;
        if (p.mode === "Append") ids.forEach((r) => s.add(r.id)); else if (p.mode === "Exclude") ids.forEach((r) => s.delete(r.id)); else { s.clear(); ids.forEach((r) => s.add(r.id)); }
        fe.log(`QSELECT ${p.type ?? "*"} ${p.property && p.property !== "*" ? `${p.property} ${p.op} ${p.value}` : "*"} → ${ids.length} matched; ${s.size} selected.`);
        fe.changed?.("selection");
        out.selected = s.size;
      }
      return out;
    }
    case "layerstate.list": return { states: statesList() };
    case "layerstate.save": {
      const n = String(p.name).trim().toUpperCase();
      const layers: Record<string, any> = {};
      for (const l of fe.layers?.layers ?? []) layers[l.name] = { visible: l.visible !== false, frozen: !!l.frozen, locked: !!l.locked };
      st.states.set(n, { layers, date: new Date().toISOString() });
      fe.log(`Layer state ${n} saved.`);
      return { selected: n, states: statesList() };
    }
    case "layerstate.restore": {
      const s = st.states.get(String(p.name).toUpperCase());
      let changed = 0;
      if (s) for (const l of fe.layers?.layers ?? []) { const e = s.layers[l.name]; if (e && (l.visible !== e.visible || !!l.frozen !== e.frozen || !!l.locked !== e.locked)) { Object.assign(l, e); changed++; } }
      fe.log(`Layer state ${p.name} restored (${changed} layer(s) changed).`);
      fe.changed?.("document");
      return { changed, states: statesList() };
    }
    case "layerstate.delete": st.states.delete(String(p.name).toUpperCase()); return { states: statesList() };
    case "layerstate.rename": {
      const old = String(p.name).toUpperCase(), n = String(p.newName ?? "").trim().toUpperCase();
      if (n && n !== old && !st.states.has(n) && st.states.has(old)) { st.states.set(n, st.states.get(old)!); st.states.delete(old); return { selected: n, states: statesList() }; }
      return { selected: old, states: statesList() };
    }
    case "layerfilter.list": return { filters: [...st.filters.entries()].sort().map(([name, filter]) => ({ name, filter })) };
    case "layerfilter.save": st.filters.set(String(p.name).toUpperCase(), String(p.filter)); return fakeDialogCall(fe, "layerfilter.list", {});
    case "layerfilter.delete": st.filters.delete(String(p.name).toUpperCase()); return fakeDialogCall(fe, "layerfilter.list", {});
    case "layers.group": {
      let n = 0;
      for (const l of fe.layers?.layers ?? []) if (groupKey(l.name) === p.group && l[p.key] !== p.value) { l[p.key] = p.value; n++; }
      fe.changed?.("document");
      return { changed: n };
    }
    case "pagesetup.get": {
      const li = typeof p.layout === "number" ? p.layout : null;
      const key = li === null ? "*MODEL*" : String(fe.info.layouts?.[li] ?? "").toUpperCase();
      const setup = { colorMode: "Color", exactFit: false, lineweightScale: 1, modelPaper: "A3", modelPortrait: false, plotArea: "Extents", plotStamp: false, ...(st.pageSetups.get(key) ?? {}) };
      return {
        isSheet: li !== null, layout: li, title: li === null ? "Page Setup — Model" : `Page Setup — ${fe.info.layouts[li]}`, ...(li !== null ? { paper: st.pageSetups.get(key)?.paper ?? "A3", portrait: !!st.pageSetups.get(key)?.portrait } : {}),
        papers: PAPERS.map(([name, w, h]) => ({ name, width: w, height: h, label: `${name} (${Math.round(w)}×${Math.round(h)} mm)`, modelLabel: `${name} (${Math.round(w)}×${Math.round(h)})` })),
        setup, scaleText: setup.modelScale ? `1:${setup.modelScale}` : "Fit", colorModes: ["Color", "Monochrome", "Grayscale"], plotAreas: ["Extents", "Display", "Limits", "Window"],
        tables: ["monochrome.ctb", "grayscale.ctb", "archi pens.ctb"], namedTables: ["archi named.stb"],
        scales: [{ value: "Fit", title: "Fit to paper" }, ...[1, 5, 10, 20, 25, 50, 75, 100, 200, 250, 500, 1000].map((r) => ({ value: `1:${r}`, title: `1:${r}` }))],
        stampTemplate: "{project}  ·  {sheet}  ·  plotted {date} {time}  ·  Oanarina Archi Tool", stampFields: ["{project}", "{number}", "{sheet}", "{date}", "{time}", "{user}", "{file}", "{style}"],
      };
    }
    case "pagesetup.set": {
      const li = typeof p.layout === "number" ? p.layout : null;
      const key = li === null ? "*MODEL*" : String(fe.info.layouts?.[li] ?? "").toUpperCase();
      const s = { ...(st.pageSetups.get(key) ?? {}), ...(p.setup ?? {}) };
      if (p.scaleText) s.modelScale = p.scaleText === "Fit" ? undefined : Number(String(p.scaleText).slice(2));
      if (li !== null && p.paper) { s.paper = p.paper; s.portrait = !!p.portrait; }
      st.pageSetups.set(key, s);
      fe.snapshot?.("Page Setup");
      return fakeDialogCall(fe, "pagesetup.get", p);
    }
    case "templates.list": {
      const t = [
        { id: "builtin:metric", name: "Metric", subtitle: "Millimetres, standard layers", symbol: "square.and.pencil" },
        { id: "builtin:metricArchitectural", name: "Metric Architectural", subtitle: "AIA-style layers, 1:20–1:200 dimension styles", symbol: "ruler" },
        { id: "builtin:imperial", name: "Imperial", subtitle: "Inches, architectural dimensions", symbol: "ruler.fill" },
        { id: "builtin:building", name: "Building", subtitle: "Levels, structural grid and sheets", symbol: "building.2" },
        ...st.templates.map((n) => ({ id: `${p.folder ?? "Templates"}\\${n}.architemplate`, name: n, subtitle: "Templates folder", symbol: "doc.badge.gearshape" })),
      ];
      return { folder: p.folder ?? null, templates: t };
    }
    case "templates.save": st.templates.push(String(p.name)); return { path: `${p.folder ?? "Templates"}\\${p.name}.architemplate` };
    case "templates.new": fe.log(String(p.id).includes("metricArchitectural") ? "New drawing from the Metric Architectural template (16 layers, 5 dimension styles)." : `New drawing from template ${p.id}.`); return fe.info;
  }
  return undefined;
}

function idle() { return { active: false, message: "Command:", keywords: [], kinds: [], preview: [] }; }
function pick(p: any, keys: string[]) { const o: any = {}; for (const k of keys) if (p?.[k] !== undefined) o[k] = p[k]; return o; }
function groupKey(n: string) { const bar = n.indexOf("|"); if (bar >= 0) return n.slice(0, bar + 1); const m = n.search(/[-_ ]/); if (m > 0) return n.slice(0, m); return n === "0" || n.toUpperCase() === "DEFPOINTS" ? "(Standard)" : n; }
function typeOf(_fe: any, r: any): string {
  const layer = String(r.layer ?? r.items?.[0]?.layer ?? "");
  const t = ({ "A-WALL": "wall", "A-DOOR": "door", "A-GLAZ": "window", "A-AREA": "space", "A-ANNO-DIMS": "dimension" } as Record<string, string>)[layer];
  if (t) return t;
  const it = r.items?.[0];
  if (it?.type === "text") return "text";
  if (it?.type === "stroke") return it.closed ? "polyline" : (it.points?.length === 2 ? "line" : "polyline");
  return "object";
}
function syncVars(fe: any) {
  const d = st.drafting, v = fe.sysvars;
  if (!v) return;
  v.GRIDMODE = d.showGrid ? "1" : "0"; v.SNAPMODE = d.gridSnap ? "1" : "0"; v.ORTHOMODE = d.ortho ? "1" : "0"; v.POLARMODE = d.polarTracking ? "1" : "0";
  v.DYNMODE = d.dynamicInput ? "1" : "0"; v.LWDISPLAY = d.lineweightDisplay ? "1" : "0";
  fe.changed?.("sysvars");
}
