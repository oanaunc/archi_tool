// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Part B of the Windows port: tool windows and UI-layer commands — block library, material library and editor, sheet set
// manager, title block, markups / compare / revision clouds, family editor, customizer, node editor and graph player,
// the JavaScript console with the full archi API (V8 worker, synchronous engine calls), script panels and plugin
// commands, the local agent server and Connect Claude, and the tutorial videos. The engine's portable commands ask for
// these with `host` notifications (docs/ENGINE-PROTOCOL.md "Tool windows"); ribbon items with a Mac `ui` target open
// them directly.
import "./partb.css";
import type { App } from "../app";
import { Ribbon } from "../ui/ribbon";
import { Panels } from "../ui/panels";
import { h, clear, button, field, checkbox, ToolWindow, fmt, type MenuItem } from "./ui";
import * as N from "./native";
import { prefs } from "../prefs";
import { ScriptConsole, ScriptLibrary, runScriptFile } from "./script-console";
import { toggleAgentServer, showConnectClaude, agentStatusBlock, planScreenshot } from "./agents";
import { showBlockLibrary, insertLibraryItem, DRAG_TYPE, type LibItem } from "./block-library";
import { renderMaterialsPanel, showMaterialLibrary, materialsHost } from "./materials";
import { renderSheetSetPanel, showTitleBlock } from "./sheets";
import { showMarkups, showCompare, showRevisionClouds } from "./review";
import { showFamilyEditor } from "./family-editor";
import { showCustomizer } from "./customizer";
import { showNodeEditor, showGraphPlayer } from "./node-editor";
import { showHelpBrowser } from "../system/help-browser";

/** What the tool windows need from the 2D plan view (canvas/plan-canvas.ts). */
export interface PlanHooks {
  el(): HTMLElement;
  view(): { cx: number; cy: number; scale: number; w: number; h: number };
  toWorld(x: number, y: number): [number, number];
  center(): [number, number];
  zoomTo(r: [number, number, number, number]): void;
  /** Adds a painter to the plan canvas overlay (world coordinates, after the hover highlight). */
  addOverlayPainter(f: (ctx: CanvasRenderingContext2D, scale: number) => void): void;
  repaint(): void;
}

/** The tutorial videos on the website (the Mac records them with TUTORIALRECORD Record). */
export const TUTORIALS_URL = "https://www.oanarinaldi.com/archi-tool.html#tutorials";

interface PlanLike { el: HTMLElement; toWorld(x: number, y: number): [number, number]; zoomTo(r: [number, number, number, number]): void }

export function installPartB(app: App, o: { plan: PlanLike; ribbon?: Ribbon; panels?: Panels }) {
  const p = o.plan as any;
  const plan: PlanHooks = {
    el: () => o.plan.el,
    view: () => { const v = p.v ?? {}; return { cx: v.cx ?? 0, cy: v.cy ?? 0, scale: v.scale || 1, w: v.w ?? o.plan.el.clientWidth, h: v.h ?? o.plan.el.clientHeight }; },
    toWorld: (x, y) => o.plan.toWorld(x, y),
    center: () => { const v = plan.view(); return [v.cx, v.cy]; },
    zoomTo: (r) => o.plan.zoomTo(r),
    addOverlayPainter: (f) => { (p.overlayPainters as unknown[] | undefined)?.push(f); },
    repaint: () => { p.refresh?.(); },
  };
  const con = new ScriptConsole(app);
  N.initScripts(app);
  N.initAgent((_id, params) => planScreenshot(app, params));
  N.onScriptPanel((spec) => showScriptPanel(app, spec));

  // ---- engine host notifications (chained after the part A dialogs) ----
  const prevHost = app.uiHooks.host;
  app.uiHooks.host = (hp: any) => handleHost(app, plan, con, hp) || !!prevHost?.(hp);
  const prevUI = app.uiHooks.ui;
  app.uiHooks.ui = (ref: string) => openToolUI(app, plan, ref) || !!prevUI?.(ref);

  // ---- shell actions ("@…") ----
  const action = app.action.bind(app);
  app.action = async (a: string) => {
    const k = a.slice(1).split(":")[0], v = a.includes(":") ? a.slice(a.indexOf(":") + 1) : "";
    switch (k) {
      case "runScript": {
        if (v) return runScriptFile(app, v);
        const f = await N.openFile(app, "Run Script", [{ name: "Scripts", extensions: ["js", "scr", "txt"] }]);
        if (f) await runScriptFile(app, f);
        return;
      }
      case "agent": return toggleAgentServer(app);
      case "connectClaude": return showConnectClaude(app);
      case "scriptConsole": { const r = await action(a); if (app.showScriptConsole) setTimeout(() => con.focus(), 0); return r; }
      case "ui": if (openToolUI(app, plan, v)) return; break;
    }
    return action(a);
  };

  // ---- ribbon: AI Agents status block, tool-window buttons, the script Library menu ----
  const R = Ribbon.prototype as any;
  R.agentStatus = function () { return agentStatusBlock(this.app); };
  const origButton = R.button;
  R.button = function (it: any) {
    const b: HTMLElement = origButton.call(this, it);
    const ref = it.ui ? String(it.ui) : "";
    if (ref && TOOL_UI.has(ref)) {
      (b as HTMLButtonElement).disabled = false;
      b.addEventListener("click", (e) => { e.stopImmediatePropagation(); openToolUI(this.app, plan, ref); }, { capture: true });
    }
    return b;
  };
  const origMenu = R.menuItems;
  R.menuItems = function (it: any): MenuItem[] {
    const items: MenuItem[] = origMenu.call(this, it);
    const dyn = (it.sections ?? []).some((s: any) => (s.items ?? []).some((x: any) => x.dynamic === "scripts"));
    if (dyn) {
      if (scriptCache.length) items.push({ separator: true }, ...scriptCache.map((f) => ({ title: f.name, symbol: "doc.text", action: () => runScriptFile(this.app, f.path) })));
      void ScriptLibrary.scripts().then((s) => { scriptCache = s; }).catch(() => {});
    }
    return items;
  };
  void ScriptLibrary.scripts().then((s) => { scriptCache = s; }).catch(() => {});

  // ---- docked panels: Materials and Sheets (Sheet Set Manager) ----
  const P = Panels.prototype as any;
  P.materials = function () { const box = h("div"); this.body.append(box); void renderMaterialsPanel(this.app, box); };
  P.sheets = function () { const box = h("div"); this.body.append(box); void renderSheetSetPanel(this.app, box); };
  o.panels && (o.panels as any).renderBody?.();
  o.ribbon && (o.ribbon as any).renderBody?.();

  // ---- block library: drop onto the plan ----
  o.plan.el.addEventListener("dragover", (e) => { if (e.dataTransfer?.types.includes(DRAG_TYPE)) { e.preventDefault(); e.dataTransfer.dropEffect = "copy"; } });
  o.plan.el.addEventListener("drop", (e) => {
    const raw = e.dataTransfer?.getData(DRAG_TYPE);
    if (!raw) return;
    e.preventDefault();
    let item: LibItem;
    try { item = JSON.parse(raw); } catch { return; }
    const r = o.plan.el.getBoundingClientRect();
    void insertLibraryItem(app, item, o.plan.toWorld(e.clientX - r.left, e.clientY - r.top));
  });

  // ---- node editor "Open in Script Console" ----
  document.addEventListener("archi:scriptConsole", (e: any) => {
    if (e.detail?.code) con.setCode(String(e.detail.code));
    if (!app.showScriptConsole) { app.showScriptConsole = true; app.emit("ui"); }
    setTimeout(() => con.focus(), 0);
  });

  // ---- part A Settings ▸ Agents asks for the agent server with a synchronous event ----
  document.addEventListener("archi:agentServer", (e: any) => {
    const d = e.detail ?? {};
    const s = N.agentLast();
    if (d.action === "status") Object.assign(d, { running: s.running, port: s.running ? s.port : d.port ?? s.port, token: s.token, infoFile: s.infoFile, handled: true });
    else if (d.action === "start" || d.action === "stop") {
      d.handled = true;
      d.message = d.action === "start" ? "Starting the agent server…" : "Stopping the agent server…";
      void (async () => {
        if (d.action === "start" && d.port) await N.agentPrefs({ port: Number(d.port) });
        if ((d.action === "start") !== N.agentLast().running) await toggleAgentServer(app);
      })();
    }
  });

  // Settings ▸ Agents (part A preferences) drive the main-process server's port and auto-start.
  const syncAgentPrefs = () => { const port = Number(prefs.get("agentPort")) || 47800, autoStart = !!prefs.get("agentAutoStart"); const s = N.agentLast(); if (s.prefPort !== port || s.autoStart !== autoStart) void N.agentPrefs({ port, autoStart }); };
  void N.agentStatus().then(syncAgentPrefs);
  prefs.on(syncAgentPrefs);

  // ---- plugin commands registered by scripts change the command list ----
  app.engine.onNotify((n: any) => {
    if (n.method === "changed" && (n.params?.what ?? []).includes("commands")) void refreshCommands(app);
  });
  return { console: con };
}

let scriptCache: N.FileEntry[] = [];

async function refreshCommands(app: App) {
  const hello = await app.tryCall("engine.hello");
  if (!hello?.commands) return;
  app.hello = hello;
  const idx: Map<string, any> = (app as any).commandIndex;
  idx.clear();
  for (const c of hello.commands) { idx.set(c.name.toUpperCase(), c); for (const a of c.aliases ?? []) if (!idx.has(a.toUpperCase())) idx.set(a.toUpperCase(), c); }
  app.emit("ui");
}

// Mac `ui` targets of ribbon / menu items that open part B windows.
const TOOL_UI = new Set(["window:BlockLibraryWindow", "window:MaterialLibraryWindow", "window:NodeEditorWindow", "window:MarkupWindow", "window:CompareWindow",
  "window:RevisionCloudWindow", "sheet:titleBlock", "sheet:connectClaude"]);

export function openToolUI(app: App, plan: PlanHooks, ref: string): boolean {
  switch (ref) {
    case "window:BlockLibraryWindow": showBlockLibrary(app, plan); return true;
    case "window:MaterialLibraryWindow": showMaterialLibrary(app); return true;
    case "window:NodeEditorWindow": showNodeEditor(app); return true;
    case "window:MarkupWindow": showMarkups(app, plan); return true;
    case "window:CompareWindow": showCompare(app, plan); return true;
    case "window:RevisionCloudWindow": showRevisionClouds(app); return true;
    case "sheet:titleBlock": if (!app.info?.layouts?.length) { app.print("The drawing has no sheets."); return true; } void showTitleBlock(app); return true;
    case "sheet:connectClaude": void showConnectClaude(app); return true;
  }
  return false;
}

/** Host notifications for part B (true when handled). */
export function handleHost(app: App, plan: PlanHooks, con: ScriptConsole, p: any): boolean {
  if (materialsHost(app, p)) return true;
  switch (p.action) {
    case "dialog":
      switch (String(p.dialog)) {
        case "blockLibrary": showBlockLibrary(app, plan); return true;
        case "materialLibrary": showMaterialLibrary(app); return true;
        case "titleBlock": void showTitleBlock(app, typeof p.layout === "number" ? p.layout : undefined); return true;
        case "markups": showMarkups(app, plan); return true;
        case "compare": showCompare(app, plan); return true;
        case "revisionClouds": showRevisionClouds(app); return true;
        case "familyEditor": void showFamilyEditor(app, p.family ?? null); return true;
        case "customizer": showCustomizer(app); return true;
        case "nodeEditor": showNodeEditor(app); return true;
        case "graphPlayer": showGraphPlayer(app); return true;
        case "connectClaude": void showConnectClaude(app); return true;
      }
      return false;
    case "scriptConsole":
      // SCRIPTCONSOLE shows or hides the console; with `code` it shows it with that script.
      if (p.code) con.setCode(String(p.code));
      app.showScriptConsole = p.code ? true : !app.showScriptConsole;
      app.emit("ui");
      if (app.showScriptConsole) setTimeout(() => con.focus(), 0);
      return true;
    case "scriptLibrary": void ScriptLibrary.reveal(app); return true;
    case "tutorials": void tutorials(app, String(p.mode ?? "Open")); return true;
    case "runScript": void runPluginCommand(app, p); return true;
  }
  return false;
}

/** Plugin command registered with archi.registerCommand: (re)loads the plugin script if needed, then calls its function. */
async function runPluginCommand(app: App, p: any) {
  const fn = String(p.function ?? "");
  if (!/^[A-Za-z_$][\w$]*$/.test(fn)) { app.print(`Plugin command: invalid function name ${fn}`); return; }
  const name = String(p.script ?? p.plugin ?? "plugin.js");
  const probe = await N.scriptEval(app, `typeof ${fn} === "function"`, name);
  if (probe.value !== "true" && p.source) {
    const r = await N.scriptEval(app, String(p.source), name);
    if (r.error) { app.print(`${name}: ${r.error}`); return; }
  }
  // Everything the plugin does (commands, archi.add/update…) becomes one undo step named after the command (UndoStep).
  await app.tryCall("undo.begin", {});
  const r = await N.scriptEval(app, `${fn}()`, name);
  await app.tryCall("undo.end", { label: String(p.command ?? p.plugin ?? fn) });
  for (const l of r.output) app.print(l);
  if (r.error) app.print(`${fn}: ${r.error}`);
  await app.refresh(["document", "selection", "history"]);
}

/** TUTORIALRECORD List | Check | Record and TUTORIALS (TutorialCommands.swift). TUTORIALS opens the offline help browser's
 *  tutorials page like the Mac; recording and checking the videos is Mac-only, so Record and Check open the website tutorials. */
async function tutorials(app: App, mode: string) {
  const open = async () => { if (app.engine.native) await app.engine.native.openExternal(TUTORIALS_URL); else window.open(TUTORIALS_URL, "_blank"); };
  if (mode === "Open") { showHelpBrowser(app, "tutorials"); return; }
  if (mode === "Record" || mode === "Check") {
    app.print("Tutorial videos are recorded and checked by the Mac app; opening the tutorial videos on the website.");
    await open();
    return;
  }
  const list = await N.tutorials();
  if (!list.length) { app.print("No tutorials found (tutorials/*.tut). The tutorial videos are on the website."); return; }
  if (mode === "List") {
    for (const t of list) app.print(`${t.name}  ${t.title} — ${t.steps} step(s), about ${Math.max(1, Math.round(t.seconds / 60))} min${t.summary ? " · " + t.summary : ""}`);
    app.print(`${list.length} tutorial(s). The videos are at ${TUTORIALS_URL}`);
    return;
  }
}

// ---- script panels (archi.panel) ----

/** Script-defined tool window: number / field / toggle / text / button items; buttons call a global function with the values. */
export function showScriptPanel(app: App, spec: any) {
  const title = String(spec?.title ?? "Script Panel");
  ToolWindow.show("script:" + title, title, { w: 300, h: 360, minW: 240, minH: 160 }, (w) => {
    const body = h("div", { class: "pb-col pb-scroll", style: { padding: "12px", gap: "8px", flex: "1" } });
    w.body.append(body);
    const values: Record<string, unknown> = {};
    const status = h("div", { class: "pb-small pb-dim" });
    for (const it of spec?.items ?? []) {
      const name = String(it.name ?? it.label ?? "");
      const label = String(it.label ?? it.name ?? "");
      switch (it.type) {
        case "number": {
          values[name] = Number(it.value ?? 0);
          const f = field({ value: fmt(Number(it.value ?? 0), 6), width: 90, onInput: (v) => { let x = parseFloat(v); if (!isFinite(x)) return; if (typeof it.min === "number") x = Math.max(it.min, x); if (typeof it.max === "number") x = Math.min(it.max, x); values[name] = x; } });
          body.append(h("div", { class: "pb-row" }, h("span", { class: "pb-label", text: label }), f));
          break;
        }
        case "field":
          values[name] = String(it.value ?? "");
          body.append(h("div", { class: "pb-row" }, h("span", { class: "pb-label", text: label }), field({ value: String(it.value ?? ""), flex: true, onInput: (v) => { values[name] = v; } })));
          break;
        case "toggle":
          values[name] = !!it.value;
          body.append(checkbox(label, !!it.value, (v) => { values[name] = v; }));
          break;
        case "text":
          body.append(h("div", { class: "pb-dim", style: { whiteSpace: "pre-wrap" }, text: String(it.value ?? it.label ?? "") }));
          break;
        case "button":
          body.append(h("div", {}, button(label || "Run", { compact: true, onClick: async () => {
            if (it.command) { await app.runCommand(String(it.command)); return; }
            if (it.call) {
              status.textContent = "";
              const r = await N.scriptEval(app, `${String(it.call)}(${JSON.stringify(values)})`, title);
              for (const l of r.output) app.print(l);
              if (r.error) status.textContent = r.error;
              await app.refresh(["document", "selection"]);
            }
          } })));
          break;
      }
    }
    body.append(status);
  });
}

export { clear };
