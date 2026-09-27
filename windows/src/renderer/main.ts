// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Renderer entry: builds the main window exactly like MainWindow.swift — title bar, ribbon, workspace (2D / 3D / split /
// sheet) with the mode badge, docked panels, layout tabs, command line and status bar — plus the start screen.
import "./styles.css";
import { App, MODES, TOGGLES } from "./app";
import { createEngine } from "./engine";
import { h, clear } from "./dom";
import { TitleBar } from "./ui/titlebar";
import { Ribbon } from "./ui/ribbon";
import { Panels } from "./ui/panels";
import { CommandLine } from "./ui/commandline";
import { StatusBar } from "./ui/statusbar";
import { StartScreen } from "./ui/start";
import { PlanCanvas } from "./canvas/plan-canvas";
import { help, closeMenus } from "./ui/menu";
import { icon } from "./icons";
import { View3D, EngineBridge } from "./view3d";

const app = new App(createEngine());
(window as any).archiApp = app; // for tests and the script console

const root = document.getElementById("app")!;
const titlebar = new TitleBar(app);
const ribbon = new Ribbon(app);
const panels = new Panels(app);
const cmd = new CommandLine(app);
const status = new StatusBar(app);
const start = new StartScreen(app);
const plan = new PlanCanvas(app);

// ---- workspace ----
const workspace = h("div", { class: "workspace" });
const badge = h("div", { class: "badge" });
const view3d = h("div", { class: "viewport3d", id: "viewport3d" });
// The 3D view (view3d/, WebGL 2) is created the first time 3D or Split is shown; the bridge keeps it in step with the
// engine (model.meshes, render.settings, selection, `changed` notifications and the 3D host actions).
let view3dWidget: View3D | null = null;
let view3dBridge: EngineBridge | null = null;
function docFolder(): string | null { const p = app.info?.path; return p ? p.replace(/[\\/][^\\/]*$/, "") : null; }
function ensure3D() {
  if (view3dWidget) return;
  const n = app.engine.native;
  try {
    view3dWidget = new View3D(view3d, {
      icon: (sf, size) => icon(sf, size),
      resolveAsset: (p) => { const d = docFolder(); return n && d ? n.fileUrl(`${d}/${p}`) : n ? n.fileUrl(p) : `assets/demo/${p}`; },
    });
    view3dBridge = new EngineBridge(view3dWidget, app.engine, { lod: 1, print: (t) => app.print(t) });
    (window as any).archiView3D = view3dWidget;
    view3dBridge.load().catch((e) => app.print(`3D view: ${e?.message ?? e}`));
  } catch (e: any) {
    view3d.append(h("span", { text: `3D view unavailable: ${e?.message ?? e}` }));
  }
}
app.on("doc", () => { view3dBridge?.load().catch(() => {}); });
function renderWorkspace() {
  clear(workspace);
  if (app.mode === "3D" || app.mode === "Split") ensure3D();
  if (app.mode === "3D") workspace.append(view3d);
  else if (app.mode === "Split") {
    const l = h("div"), r = h("div");
    l.append(plan.el); r.append(view3d);
    workspace.append(h("div", { class: "split" }, l, h("div", { class: "vsep" }), r));
  } else workspace.append(plan.el);
  workspace.append(badge);
  renderBadge();
}
function renderBadge() {
  clear(badge);
  for (const m of MODES) {
    const b = h("button", { class: app.mode === m ? "sel" : "", text: m });
    help(b, `Show ${m}`);
    b.addEventListener("click", () => { if (m === "Sheet" && app.activeLayout === 0 && app.info?.layouts.length) app.activeLayout = 1; if (m !== "Sheet") app.activeLayout = 0; app.setUI("mode", m); });
    badge.append(b);
  }
  if (app.mode === "2D" || app.mode === "Split") badge.append(h("span", { class: "lvl", text: app.info?.currentLevel ?? "" }));
}

// ---- panel resize handle ----
const handle = h("div", { class: "panel-handle" });
help(handle, "Drag to resize the panels · double-click for the default width");
handle.addEventListener("mousedown", (e) => {
  const x0 = e.clientX, w0 = app.panelWidth;
  const mv = (ev: MouseEvent) => { panels.el.style.width = Math.min(620, Math.max(220, w0 - (ev.clientX - x0))) + "px"; };
  const up = (ev: MouseEvent) => { removeEventListener("mousemove", mv); removeEventListener("mouseup", up); app.setUI("panelWidth", Math.min(620, Math.max(220, w0 - (ev.clientX - x0)))); };
  addEventListener("mousemove", mv); addEventListener("mouseup", up);
});
handle.addEventListener("dblclick", () => app.setUI("panelWidth", 300));

// ---- layout tabs (Model, Sheet 1, +) ----
const layoutTabs = h("div", { class: "layout-tabs" });
function renderLayoutTabs() {
  clear(layoutTabs);
  const titles = ["Model", ...(app.info?.layouts ?? [])];
  const cur = app.mode === "Sheet" ? app.activeLayout : 0;
  titles.forEach((t, i) => {
    const b = h("button", { class: "lt" + (cur === i ? " sel" : "") }, i === 0 ? icon("square.grid.3x3", 10) : null, h("span", { text: t }));
    help(b, i === 0 ? "Model space" : `Sheet ${t} — right-click for options`);
    b.addEventListener("click", () => { app.activeLayout = i; app.setUI("mode", i === 0 ? (app.mode === "Sheet" ? "2D" : app.mode) : "Sheet"); renderLayoutTabs(); });
    layoutTabs.append(b);
  });
  const add = h("button", { class: "lt" }, icon("plus", 11, 2)); help(add, "New sheet (LAYOUT New)");
  add.addEventListener("click", () => app.runCommand("LAYOUT New"));
  layoutTabs.append(add);
}

// ---- command search (Ctrl+K) ----
function commandSearch() {
  let idx = 0;
  const inp = h("input", { placeholder: "Search commands…", spellcheck: false }) as HTMLInputElement;
  const rows = h("div", { class: "rows" });
  const ov = h("div", { class: "overlay" }, h("div", { class: "palette" }, inp, rows));
  const results = () => {
    const q = inp.value.trim().toLowerCase();
    return app.hello.commands.filter((c) => !q || c.name.toLowerCase().includes(q) || c.summary.toLowerCase().includes(q) || c.aliases.some((a) => a.toLowerCase() === q)).slice(0, 60);
  };
  const render = () => {
    clear(rows);
    results().forEach((c, i) => {
      const r = h("div", { class: "row" + (i === idx ? " sel" : "") }, h("span", { class: "n", text: c.name }), h("span", { class: "c", text: c.category }), h("span", { class: "s", text: c.summary }));
      r.addEventListener("click", () => { ov.remove(); app.runCommand(c.name); });
      rows.append(r);
    });
  };
  inp.addEventListener("input", () => { idx = 0; render(); });
  inp.addEventListener("keydown", (e) => {
    e.stopPropagation();
    const n = results().length;
    if (e.key === "Escape") ov.remove();
    else if (e.key === "ArrowDown") { idx = Math.min(n - 1, idx + 1); render(); e.preventDefault(); }
    else if (e.key === "ArrowUp") { idx = Math.max(0, idx - 1); render(); e.preventDefault(); }
    else if (e.key === "Enter") { const c = results()[idx]; ov.remove(); if (c) app.runCommand(c.name); }
  });
  ov.addEventListener("mousedown", (e) => { if (e.target === ov) ov.remove(); });
  document.body.append(ov); render(); inp.focus();
}
document.addEventListener("archi:commandSearch", commandSearch);

// ---- JavaScript console (the archi API runs in the shell's V8 and calls the engine) ----
const consoleOut = h("div", { class: "out" });
const consoleIn = h("textarea", { placeholder: "archi.run(\"LINE 0,0 1000,0 \")  ·  await archi.call(\"doc.info\")  —  Ctrl+Enter runs" }) as HTMLTextAreaElement;
const scriptConsole = h("div", { class: "console" }, consoleOut, consoleIn);
const archiApi = { run: (line: string) => app.runCommand(line), call: (m: string, p?: unknown) => app.engine.call(m, p ?? {}), print: (s: unknown) => { consoleOut.append(String(s) + "\n"); }, get selection() { return app.selection.ids; } };
consoleIn.addEventListener("keydown", async (e) => {
  e.stopPropagation();
  if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
    const src = consoleIn.value; consoleOut.append("› " + src + "\n");
    try { const r = await new Function("archi", `return (async () => { ${/\breturn\b/.test(src) ? src : "return (" + src + ")"} })()`)(archiApi); if (r !== undefined) consoleOut.append(JSON.stringify(r, null, 1) + "\n"); }
    catch (err: any) { consoleOut.append(`Error: ${err?.message ?? err}\n`); }
    consoleOut.scrollTop = 1e9;
  }
});

// ---- layout ----
const mainRow = h("div", { class: "main-row" }, workspace);
function layout() {
  clear(root);
  root.append(titlebar.el);
  if (!app.cleanScreen) root.append(ribbon.el, h("div", { class: "hsep" }));
  mainRow.replaceChildren(workspace);
  if (app.showPanels && !app.cleanScreen) { panels.el.style.width = app.panelWidth + "px"; mainRow.append(handle, panels.el); }
  root.append(mainRow);
  if (!app.cleanScreen) { renderLayoutTabs(); root.append(layoutTabs); }
  if (app.showScriptConsole) root.append(h("div", { class: "hsep" }), scriptConsole);
  root.append(h("div", { class: "hsep" }), cmd.el, h("div", { class: "hsep" }), status.el);
  document.body.append(start.el);
}
let lastMode = app.mode;
app.on("ui", () => { layout(); if (lastMode !== app.mode) { lastMode = app.mode; renderWorkspace(); } else renderBadge(); });
app.on("doc", () => { renderBadge(); renderLayoutTabs(); });
app.hostView = { zoomTo: (r) => plan.zoomTo(r), pan: (d) => { plan.view.cx += d[0]; plan.view.cy += d[1]; plan.refresh(); } };
app.canvas = { zoomExtents: () => plan.zoomExtents(), zoomBy: (f) => plan.zoomBy(f), zoomWindow: () => plan.zoomWindow(), focus: () => plan.focus(), refresh: () => plan.refresh() };
layout(); renderWorkspace();

// ---- keyboard (AutoCAD-style: just start typing) ----
addEventListener("keydown", (e) => {
  const t = e.target as HTMLElement;
  if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA") && t !== cmd.input) return;
  const ctrl = e.ctrlKey || e.metaKey;
  const fkeys: Record<string, string> = { F3: "OSMODE", F7: "GRIDMODE", F8: "ORTHOMODE", F9: "SNAPMODE", F10: "POLARMODE", F11: "OTRACK", F12: "DYNMODE" };
  if (fkeys[e.key]) { e.preventDefault(); app.toggleVar(fkeys[e.key], TOGGLES.find((x) => x.varName === fkeys[e.key])?.title); return; }
  if (e.key === "F2") { e.preventDefault(); return; }
  if (ctrl) {
    const k = e.key.toLowerCase();
    const map: Record<string, () => void> = {
      z: () => app.undo(), y: () => app.redo(), s: () => app.save(e.shiftKey), o: () => app.open(), p: () => app.runCommand("PLOT"), a: () => app.selectAll(),
      k: () => commandSearch(), "0": () => app.action("@cleanScreen"), n: () => app.engine.native ? app.engine.native.newWindow({ kind: "start" }) : app.newDocument(),
      "=": () => plan.zoomBy(1.5), "+": () => plan.zoomBy(1.5), "-": () => plan.zoomBy(1 / 1.5), c: () => app.runCommand("COPYCLIP"), v: () => app.runCommand("PASTECLIP"), x: () => app.runCommand("CUTCLIP"),
    };
    if (map[k]) { e.preventDefault(); map[k](); }
    return;
  }
  if (t === cmd.input) return;
  if (e.key === "Escape") { closeMenus(); if (!plan.cancelGrip()) app.cancel(); e.preventDefault(); return; }
  if (e.key === "Delete") { if (app.isIdle && app.selection.ids.length) app.runCommand("ERASE"); e.preventDefault(); return; }
  if (e.key === "Enter" || (e.key === " " && !e.repeat && app.commandInput === "" && document.activeElement !== plan["overlay"])) { e.preventDefault(); app.submitLine(""); return; }
  if (e.key === " " && document.activeElement === plan["overlay"]) return; // Space+drag pans; released without drag repeats (keyup)
  if (e.key.length === 1 && !e.altKey) { e.preventDefault(); cmd.typeKey(e.key); }
});
addEventListener("keyup", (e) => { if (e.key === " " && document.activeElement === plan["overlay"] && !(plan as any).panLast) app.submitLine(""); });

// ---- start ----
(async () => {
  await app.init();
  const req = (await app.engine.native?.initialRequest()) ?? { kind: new URLSearchParams(location.search).get("open") ? "open" : "start", path: new URLSearchParams(location.search).get("open") ?? undefined };
  if (req.kind === "open" && req.path) await app.open(req.path);
  else if (req.kind === "sample") await app.openSample(req.path ?? "Cedar House");
  else if (req.kind === "new") await app.newDocument(req.path ?? "metric");
  else { app.showStart = true; app.emit("start"); }
  document.body.classList.add("ready");
})();
