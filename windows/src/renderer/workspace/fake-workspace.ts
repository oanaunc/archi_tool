// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Fixture-engine side of the panels and workspace module: recorded Cedar House answers (ws-*.json from
// ./scripts/q.sh engine) where they exist, otherwise a small simulation over the fixture engine's drawing, and the
// portable workspace commands (Host/EngineWorkspaceCommands.swift) answering with the same `host` notifications, so the
// shell can be exercised in the browser test page. Never used inside the Electron app.

export const WS_COMMANDS: { name: string; aliases: string[]; category: string; summary: string }[] = [
  { name: "NOTIFICATIONS", aliases: ["WARNINGS", "NOTIFYCENTER"], category: "Inquiry", summary: "Notifications centre: model warnings (overlaps, unhosted openings, family errors, missing blocks) — click one to zoom to it." },
  { name: "NAVIGATOR", aliases: ["OVERVIEW", "MINIMAP"], category: "View", summary: "Navigator: overview map of the whole drawing with the visible area; drag the rectangle to pan." },
  { name: "ADCENTER", aliases: ["DESIGNCENTER", "ADC"], category: "Insert", summary: "Design Center: browses another drawing's blocks, layers, linetypes, styles and materials and adds them here." },
  { name: "OUTLINERPANEL", aliases: ["OUTLINERWINDOW", "SHOWOUTLINER"], category: "3D", summary: "Outliner window: the tree of groups, components, blocks and model groups; click selects, double-click zooms, filter by name." },
  { name: "FLOATPANEL", aliases: ["UNDOCKPANEL", "PANELFLOAT"], category: "View", summary: "Floats a panel (Properties, Layers, Levels, Browser, Materials, Tools, Sheets, History) in its own window." },
  { name: "TILEDVIEWS", aliases: ["VPTILE", "TILEVIEWS"], category: "View", summary: "Tiled model views: 2, 3 or 4 views (plan, 3D, section, elevations), each with its own zoom and pan." },
  { name: "DVIEW", aliases: ["DV", "PLANTWIST"], category: "View", summary: "Rotates (twists) the 2D plan display; model coordinates are unchanged. DVIEW TWist 30, DVIEW Off." },
  { name: "PERSPECTIVE", aliases: ["PROJECTION"], category: "View", summary: "3D projection: 1 = perspective, 0 = parallel (orthographic)." },
  { name: "KEYBOARDNAV", aliases: ["KEYCURSOR", "KEYBOARDHELP"], category: "Help", summary: "Keyboard-only drawing: arrow keys move the crosshair at prompts (Shift ×10, Alt ÷10; Alt+arrows when idle), Enter picks, Tab selects under the crosshair; sets the step." },
  { name: "ASSISTANT", aliases: ["AI", "AICHAT", "CHAT", "ASKAI"], category: "Scripting", summary: "AI assistant panel: Claude or a local model (Ollama) edits the drawing with commands; bulk changes ask for confirmation; everything is undoable." },
  { name: "LANGUAGE", aliases: ["UILANGUAGE", "LIMBA", "SPRACHE", "LANGUE", "IDIOMA", "LINGUA"], category: "Settings", summary: "Interface language of the ribbon: Auto (Windows), English, Română, Deutsch, Français, Español, Italiano. Commands stay English." },
  { name: "EXPORTSETTINGS", aliases: ["SETTINGSOUT"], category: "Settings", summary: "Exports all preferences (theme, shortcuts, toolbar, workspaces, snippets…) to a settings file for another computer." },
  { name: "IMPORTSETTINGS", aliases: ["SETTINGSIN"], category: "Settings", summary: "Imports preferences exported by EXPORTSETTINGS (restart to apply everything)." },
  { name: "CMDLINEOPTIONS", aliases: ["CLISETTINGS", "COMMANDLINEOPTIONS", "CLIFLOAT"], category: "Settings", summary: "Command line appearance: text Size, history Lines shown, background Opacity; Float it over the canvas or Dock it at the bottom." },
  { name: "CRASHREPORTS", aliases: ["CRASHREPORT", "CRASHLOG"], category: "Settings", summary: "Opt-in crash reports: On, Off, Status, Show the saved reports (reviewed and sent only by you), Clear." },
  { name: "FILETAB", aliases: [], category: "View", summary: "Shows the file tab bar with one tab per open drawing." },
  { name: "FILETABCLOSE", aliases: [], category: "View", summary: "Hides the file tab bar." },
  { name: "WINDOWTABS", aliases: ["DOCTABS"], category: "View", summary: "Window tabs: Merge all drawing windows into tabs, or open new drawings in Tabs / Windows." },
  { name: "SYSWINDOWS", aliases: ["ARRANGEWINDOWS", "TILEWINDOWS", "WINDOWS"], category: "View", summary: "Arranges the open drawing windows: Vertical (side by side), Horizontal, Cascade, Tabs or Separate windows." },
  { name: "FULLSCREEN", aliases: ["FS"], category: "View", summary: "Enters or leaves full screen for this drawing window." },
];
const PANELS = ["Properties", "Layers", "Levels", "Browser", "Materials", "Tools", "Sheets", "History", "Selection", "Navigator", "Alerts", "Quick Props", "Inspector", "Content"];
const LANGS: [string, string][] = [["en", "English"], ["ro", "Română"], ["de", "Deutsch"], ["fr", "Français"], ["es", "Español"], ["it", "Italiano"]];
const uiPrefs: Record<string, string> = {};
let undoMark: number | null = null;

function kw(v: string | undefined, list: string[], def: string) {
  if (!v) return def;
  const l = v.toLowerCase();
  return list.find((k) => k.toLowerCase() === l) ?? list.find((k) => k.replace(/[^A-Z0-9]/g, "").toLowerCase() === l) ?? list.find((k) => k.toLowerCase().startsWith(l)) ?? def;
}
function recorded(fe: any, method: string, pred: (p: any) => boolean = () => true) {
  const r = fe.rec?.(method, (p: any) => pred(p ?? {}));
  return r ? JSON.parse(JSON.stringify(r.result)) : undefined;
}

export function fakeWorkspaceCall(fe: any, method: string, p: any): any {
  const host = (params: any) => fe.emit("host", params);
  const idle = { active: false, message: "Command:", keywords: [], kinds: [], preview: [] };
  switch (method) {
    case "engine.hello": {
      const h = fe.hello;
      if (h && Array.isArray(h.commands)) for (const c of WS_COMMANDS) if (!h.commands.some((x: any) => x.name === c.name)) h.commands.push({ ...c, modifies: c.name === "DVIEW" });
      return undefined;
    }
    case "ui.prefs": Object.assign(uiPrefs, p?.values ?? {}); return undefined;
    case "command.run": {
      const toks = String(p.line ?? "").trim().split(/\s+/);
      const name = toks[0]?.toUpperCase() ?? "";
      const def = WS_COMMANDS.find((c) => c.name === name || c.aliases.includes(name));
      if (!def) return undefined;
      fe.log(`Command: ${name}`);
      const arg = toks.slice(1).join(" ");
      switch (def.name) {
        case "NOTIFICATIONS": { const n = alerts(fe, false, []).items.filter((i: any) => i.severity !== "info").length; fe.log(n ? `${n} warning(s).` : "No warnings."); host({ action: "showPanel", panel: "Alerts" }); break; }
        case "NAVIGATOR": host({ action: "showPanel", panel: "Navigator", mode: "2D" }); break;
        case "ADCENTER": host({ action: "showPanel", panel: "Content" }); break;
        case "OUTLINERPANEL": host({ action: "dialog", dialog: "outliner" }); break;
        case "FLOATPANEL": host({ action: "floatPanel", panel: kw(arg, PANELS, uiPrefs.panelTab ?? "Properties") }); break;
        case "TILEDVIEWS": host({ action: "tiledViews", arrangement: kw(arg, ["2", "Stacked", "3", "4", "Single"], "4") }); break;
        case "DVIEW": {
          if (/^off$/i.test(toks[1] ?? "")) { fe.sysvars.VIEWTWIST = "0"; fe.log("View twist off."); }
          else { const a = Number(toks[2] ?? toks[1]) || 0; fe.sysvars.VIEWTWIST = String(a); fe.log(`View twist ${a}°.`); }
          fe.changed("document"); break;
        }
        case "PERSPECTIVE": { const v = toks[1] === "0" ? 0 : 1; host({ action: "show3D" }); host({ action: "setView", view: v ? "perspective" : "ortho" }); break; }
        case "KEYBOARDNAV": {
          const v = Math.round(Number(toks[1] ?? uiPrefs.keyboardCursorStep ?? 10));
          if (!(v >= 1 && v <= 200)) { fe.log("Enter 1–200 pixels."); break; }
          uiPrefs.keyboardCursorStep = String(v);
          host({ action: "preference", key: "keyboardCursorStep", value: v });
          fe.log("  At a point prompt the arrow keys move the crosshair (Shift ×10, Alt ÷10); Enter picks the snapped point.");
          break;
        }
        case "ASSISTANT": host({ action: "dialog", dialog: "assistant" }); break;
        case "LANGUAGE": {
          const names = ["Auto", ...LANGS.map((l) => l[1])];
          const k = kw(arg, names, "Auto");
          const code = k === "Auto" ? "auto" : LANGS.find((l) => l[1] === k)?.[0] ?? "en";
          uiPrefs.uiLanguage = code;
          host({ action: "preference", key: "uiLanguage", value: code });
          fe.log(`Interface language: ${k}.`);
          break;
        }
        case "EXPORTSETTINGS": host({ action: "exportSettings" }); break;
        case "IMPORTSETTINGS": host({ action: "importSettings" }); break;
        case "CMDLINEOPTIONS": {
          const cur = { fontSize: Number(uiPrefs["cmdline.fontSize"] ?? 11), lines: Number(uiPrefs["cmdline.lines"] ?? 4), opacity: Number(uiPrefs["cmdline.opacity"] ?? 0.55), floating: uiPrefs["cmdline.floating"] === "1" };
          const k = kw(toks[1], ["Size", "Lines", "Opacity", "Float", "Dock", "Reset"], cur.floating ? "Dock" : "Float");
          const v = Number(toks[2]);
          if (k === "Size") { if (!(v >= 8 && v <= 20)) { fe.log("Enter 8 to 20."); break; } cur.fontSize = v; }
          if (k === "Lines") { if (!(v >= 1 && v <= 40)) { fe.log("Enter 1 to 40."); break; } cur.lines = v; }
          if (k === "Opacity") { if (!(v >= 0.1 && v <= 1)) { fe.log("Enter 0.1 to 1."); break; } cur.opacity = v; }
          if (k === "Float") cur.floating = true;
          if (k === "Dock") cur.floating = false;
          if (k === "Reset") Object.assign(cur, { fontSize: 11, lines: 4, opacity: 0.55, floating: false });
          Object.assign(uiPrefs, { "cmdline.fontSize": String(cur.fontSize), "cmdline.lines": String(cur.lines), "cmdline.opacity": String(cur.opacity), "cmdline.floating": cur.floating ? "1" : "0" });
          host({ action: "preference", key: "cmdline", value: { ...cur, reset: k === "Reset" } });
          fe.log(`Command line: ${cur.fontSize} pt, ${cur.lines} line(s), opacity ${cur.opacity}, ${cur.floating ? "floating" : "docked"}.`);
          break;
        }
        case "CRASHREPORTS": host({ action: "crashReports", op: kw(toks[1], ["On", "Off", "Status", "Show", "Clear"], "Status") }); break;
        case "FILETAB": host({ action: "fileTabs", on: true }); fe.log("File tabs on."); break;
        case "FILETABCLOSE": host({ action: "fileTabs", on: false }); fe.log("File tabs off."); break;
        case "WINDOWTABS": {
          const k = kw(toks[1], ["Merge", "Tabs", "Windows"], "Merge");
          host({ action: "windowTabs", op: k });
          fe.log(k === "Merge" ? "Drawing windows merged into tabs." : k === "Tabs" ? "New drawings open as tabs." : "New drawings open in their own windows.");
          break;
        }
        case "SYSWINDOWS": host({ action: "arrangeWindows", mode: kw(toks[1], ["Vertical", "Horizontal", "Cascade", "Tabs", "Separate"], "Vertical") }); break;
        case "FULLSCREEN": host({ action: "fullScreen" }); break;
      }
      return idle;
    }
    case "alerts.get": return alerts(fe, !!p?.showInfo, p?.dismissed ?? []);
    case "navigator.get": {
      const lines: number[][] = [];
      for (const e of fe.decoded ?? []) for (const it of e.items ?? []) if (it.type === "stroke" && it.points?.length > 1) lines.push(it.points.flatMap((q: number[]) => [q[0], q[1]]));
      return { lines: lines.slice(0, 20000), extents: fe.info?.extents ?? null, level: 0 };
    }
    case "outliner.get": {
      const r = recorded(fe, "outliner.get");
      const f = String(p?.filter ?? "").toLowerCase();
      const nodes = (r?.nodes?.length ? r.nodes : [{ name: "Kitchen island <KITCHEN>", kind: "component", symbol: "cube", id: 1, selected: false, children: [{ name: "Worktop", kind: "line", symbol: "cube.transparent", id: null, selected: false, children: [] }] },
        { name: "Group", kind: "group", symbol: "square.on.square.dashed", id: 2, selected: false, children: [] }]).filter((n: any) => !f || String(n.name).toLowerCase().includes(f));
      return { nodes, empty: nodes.length === 0 };
    }
    case "content.kinds": return undefined;
    case "content.scan": {
      const r = recorded(fe, "content.scan");
      const name = String(p?.path ?? "").split(/[\\/]/).pop()?.replace(/\.[^.]+$/, "") || "Drawing";
      return r ? { ...r, path: p?.path, name } : { name, path: p?.path, kinds: [
        { kind: "Blocks", symbol: "square.on.square.dashed", names: ["Chair", "Table"] }, { kind: "Layers", symbol: "square.3.layers.3d", names: ["0", "A-WALL", "A-DOOR", "FURN"] },
        { kind: "Linetypes", symbol: "line.3.horizontal", names: ["Continuous", "Dashed"] }, { kind: "Text Styles", symbol: "textformat", names: ["Standard"] },
        { kind: "Dimension Styles", symbol: "ruler", names: ["ISO-25"] }, { kind: "Materials", symbol: "paintpalette", names: ["Oak", "Concrete"] }] };
    }
    case "content.add": {
      const scan = fakeWorkspaceCall(fe, "content.scan", { path: p?.path });
      const all: string[] = scan.kinds.find((k: any) => k.kind === p?.kind)?.names ?? [];
      const names: string[] = p?.all ? all : (p?.names ?? []);
      const added: string[] = [];
      if (p?.kind === "Layers") for (const n of names) if (!fe.layers.layers.some((l: any) => l.name.toLowerCase() === n.toLowerCase())) { fe.layers.layers.push({ name: n, color: "#ffffff", linetype: "Continuous", lineweight: 0.25, visible: true, frozen: false, locked: false, count: 0 }); added.push(n); }
      if (added.length) { fe.snapshot("Design Center"); fe.changed("document"); }
      return { added, message: added.length ? `Added ${added.length}: ${added.join(", ")}` : "Nothing new: those names already exist here." };
    }
    case "view.projection": {
      const r = recorded(fe, "view.projection", (q) => String(q.view).toLowerCase() === String(p?.view).toLowerCase());
      if (r) return r;
      const v = String(p?.view ?? "");
      if (!["Section", "North", "South", "East", "West"].includes(v)) throw { code: -32602, message: "view must be Section, North, South, East or West" };
      const title = v === "Section" ? "Section A-A" : `${v} Elevation`;
      const st = { color: "#000000", lineweight: 0.35, dash: [] };
      return { view: v, title, items: [{ type: "stroke", points: [[0, 0], [12000, 0], [12000, 3000], [6000, 5500], [0, 3000]], closed: true, style: st }, { type: "stroke", points: [[-2000, 0], [14000, 0]], closed: false, style: st }], bounds: [-2000, 0, 14000, 5500] };
    }
    case "macro.buttons": { try { return JSON.parse(localStorage.getItem("archi.fake.macroButtons") ?? "[]"); } catch { return []; } }
    case "macro.run": {
      const line = String(p?.macro ?? "").replace(/^(\^C)+/i, "").replace(/;/g, " ").trim();
      return fe.call("command.run", { line });
    }
    case "undo.begin": undoMark = fe.undo.length; return { ok: true };
    case "undo.end": {
      if (undoMark === null) return { collapsed: false };
      const mark = undoMark; undoMark = null;
      if (fe.undo.length <= mark) return { collapsed: false };
      const first = fe.undo[mark];
      fe.undo.splice(mark, fe.undo.length - mark, { label: String(p?.label ?? "Plugin"), raw: first.raw });
      fe.changed("document");
      return { collapsed: true, label: String(p?.label ?? "Plugin") };
    }
    case "assistant.context":
      return recorded(fe, "assistant.context") ?? { system: "You are the assistant inside Oanarina Archi Tool…\nCommands by category:\nDraw: LINE CIRCLE RECTANG", context: "Drawing: Drawing1.\nSelection: none.\n", toolName: "run_commands", toolDescription: "Runs Oanarina Archi Tool command lines on the open drawing, in order." };
    case "assistant.assess": {
      const n = (p?.commands ?? []).length;
      const bulk = n > Number(p?.bulkLimit ?? 25);
      return { added: n, removed: 0, modified: 0, total: n, summary: `${n} added, 0 modified, 0 deleted`, bulk, output: [] };
    }
    case "assistant.apply": {
      const cmds: string[] = p?.commands ?? [];
      return (async () => { for (const c of cmds) { const st = await fe.call("command.run", { line: c }); if (st?.active) await fe.call("input.key", { key: "Escape" }); } return { count: cmds.length, output: [] }; })();
    }
  }
  return undefined;
}

/** Simulated model warnings over the fixture drawing (the recorded Cedar House answer is used when that drawing is open). */
function alerts(fe: any, showInfo: boolean, dismissed: string[]) {
  const ents = (fe.raw ?? []).filter((e: any) => e.id);
  const out: any[] = [];
  const bounds = (e: any) => { const d = (fe.decoded ?? []).find((x: any) => x.id === e.id); return d ? d.bounds : null; };
  if (ents.length >= 2) out.push({ key: `WALL-OVERLAP:${ents[0].id},${ents[1].id}:Walls overlap`, severity: "warning", code: "WALL-OVERLAP", message: "Walls overlap", ids: [Number(ents[0].id), Number(ents[1].id)], bounds: bounds(ents[0]), level: 0 });
  if (ents.length) out.push({ key: `LAYER-MISSING:${ents[0].id}:Layer X is not in the layer table`, severity: "info", code: "LAYER-MISSING", message: "Layer X is not in the layer table", ids: [Number(ents[0].id)], bounds: bounds(ents[0]), level: null });
  const items = out.filter((i) => !dismissed.includes(i.key) && (showInfo || i.severity !== "info"));
  return { items, count: items.length, warnings: out.filter((i) => i.severity !== "info").length, total: out.length };
}
