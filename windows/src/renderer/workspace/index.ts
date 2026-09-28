// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Panels and workspace: the Alerts, Navigator and Content panels (workspace/panels.ts), floating panels (float.ts),
// tiled views (tiles.ts), the Outliner and AI Assistant windows, the file tab bar and window tabs / arrangement / full
// screen, the keyboard crosshair (SYS-029), the command line appearance (CMDLINEOPTIONS), the interface language
// (LANGUAGE), settings export / import, opt-in crash reports, and the progress of long engine calls for the status
// bar. The engine's portable commands (Host/EngineWorkspaceCommands.swift) ask for these with `host` notifications
// (docs/ENGINE-PROTOCOL.md "Panels and workspace"); the shell keeps the settings and tells the engine with ui.prefs.
import "./workspace.css";
import type { App } from "../app";
import { h, clear } from "../dom";
import { icon } from "../icons";
import { help, showMenu } from "../ui/menu";
import { cmdAppearance } from "../ui/commandline";
import { Sheet, button } from "../partb/ui";
import { WS, type WinInfo } from "./native";
import { progress, trackEngine } from "./progress";
import { planHooks, invalidateNavigator, type PlanHooks } from "./panels";
import { floatPanel, isFloating, restoreFloatingPanels, floatingWindow } from "./float";
import { TiledViews, tileState, arrangementFor, arrangementTitle } from "./tiles";
import { showOutliner } from "./outliner";
import { showAssistant } from "./assistant";
import { LANGUAGES, languageSetting, setLanguageSetting, systemLanguage, resolvedLanguage } from "./l10n";

export { t, translateMenu } from "./l10n";
export { progress };

const PANEL_TABS = ["Properties", "Layers", "Levels", "Browser", "Materials", "Tools", "Sheets", "History", "Selection", "Navigator", "Alerts", "Quick Props", "Inspector", "Content"];
const ISSUES = "https://github.com/oanaunc/archi_tool/issues/new";
function ls(k: string, d: string) { try { return localStorage.getItem(k) ?? d; } catch { return d; } }
function lsSet(k: string, v: string) { try { localStorage.setItem(k, v); } catch {} }

export interface WorkspaceHooks {
  plan: PlanHooks & { el: HTMLElement; overlay: HTMLElement; mouse(): [number, number] | null };
  view3d: HTMLElement;
  ensure3D(): void;
  commandLine: { el: HTMLElement; relayout(): void };
  /** Re-renders the workspace (the tiled views changed). */
  relayout(): void;
}

// ---- file tabs (FileTabs, FILETAB / FILETABCLOSE) ----
class FileTabs {
  el = h("div", { class: "ws-filetabs" });
  private list: WinInfo[] = [];
  constructor(private app: App) {
    WS.onWindows((l) => { this.list = l; this.render(); });
    void WS.windows().then((l) => { this.list = l; this.render(); });
  }
  get visible() { return ls("archi.fileTabs", "0") === "1"; }
  set visible(v: boolean) { lsSet("archi.fileTabs", v ? "1" : "0"); this.render(); this.app.emit("ui"); }
  render() {
    clear(this.el);
    this.el.style.display = this.visible ? "" : "none";
    if (!this.visible) return;
    for (const w of this.list) {
      const close = h("button", { class: "x" }, icon("xmark", 9, 2));
      help(close, `Close ${w.title}`);
      close.addEventListener("click", (e) => { e.stopPropagation(); void WS.close(w.id); });
      const tab = h("div", { class: "ft" + (w.focused ? " sel" : ""), role: "tab", "aria-selected": String(w.focused) }, h("span", { class: "t", text: w.title + (w.dirty ? " •" : "") }), close);
      help(tab, w.summary ?? (w.path ?? "Not saved yet"));
      tab.addEventListener("click", () => void WS.focus(w.id));
      this.el.append(tab);
    }
    const add = h("button", { class: "ft add" }, icon("plus", 11, 2));
    help(add, "New drawing window");
    add.addEventListener("click", () => void this.app.action("@newWindow:start"));
    this.el.append(add);
  }
}

// ---- keyboard crosshair (KeyboardCursor, SYS-029) ----
function installKeyboardCrosshair(app: App, plan: WorkspaceHooks["plan"]) {
  let pos: [number, number] | null = null;
  let active = false;
  const step = () => Math.max(1, Math.min(200, Number(ls("archi.keyboardCursorStep", "10")) || 10));
  const fire = (type: string, p: [number, number]) => {
    const r = plan.overlay.getBoundingClientRect();
    plan.overlay.dispatchEvent(new MouseEvent(type, { clientX: r.left + p[0], clientY: r.top + p[1], bubbles: true, button: 0, buttons: type === "mousedown" ? 1 : 0 }));
  };
  plan.overlay.addEventListener("mousemove", (e) => { if (e.isTrusted) active = false; });
  addEventListener("keydown", (e) => {
    if (!plan.overlay.isConnected || (app.mode !== "2D" && app.mode !== "Split")) return;
    const t = e.target as HTMLElement;
    const inField = t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA") && !t.closest(".cmdline");
    if (inField || app.commandInput !== "") return;
    const req = app.prompt;
    const pointPrompt = req.active && req.kinds.includes("point");
    if ((e.key === "Enter" || e.key === "Tab") && active && pos) {
      if (e.key === "Enter" && pointPrompt) { fire("mousedown", pos); fire("mouseup", pos); e.preventDefault(); e.stopImmediatePropagation(); }
      else if (e.key === "Tab" && (app.isIdle || req.kinds.includes("selection"))) { fire("mousedown", pos); fire("mouseup", pos); e.preventDefault(); e.stopImmediatePropagation(); }
      return;
    }
    const dirs: Record<string, [number, number]> = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
    const d = dirs[e.key];
    if (!d || e.ctrlKey || e.metaKey) return;
    if (!(pointPrompt || (app.isIdle && e.altKey))) return;
    let s = step();
    if (e.shiftKey) s *= 10;
    if (e.altKey && pointPrompt) s = Math.max(1, s / 10);
    const r = plan.overlay.getBoundingClientRect();
    const cur = (active && pos) || plan.mouse() || [r.width / 2, r.height / 2];
    pos = [Math.min(Math.max(cur[0] + d[0] * s, 0), r.width - 1), Math.min(Math.max(cur[1] + d[1] * s, 0), r.height - 1)];
    active = true;
    fire("mousemove", pos);
    e.preventDefault(); e.stopImmediatePropagation();
  }, true);
}

// ---- floating command line (FloatingCommandLine) ----
function applyCmdline(cl: WorkspaceHooks["commandLine"], app: App) {
  cmdAppearance.font = Number(ls("archi.cmdline.fontSize", "11")) || 11;
  cmdAppearance.lines = Number(ls("archi.cmdline.lines", "4")) || 4;
  cmdAppearance.opacity = Number(ls("archi.cmdline.opacity", "0.55")) || 0.55;
  cl.relayout();
  const floating = ls("archi.cmdline.floating", "0") === "1";
  cl.el.classList.toggle("ws-floating", floating);
  let grip = cl.el.querySelector(".ws-clgrip") as HTMLElement | null;
  if (floating && !grip) {
    grip = h("div", { class: "ws-clgrip" }, h("span", { class: "cap" }));
    help(grip, "Drag to move the command line · double-click to dock it");
    grip.addEventListener("dblclick", () => { lsSet("archi.cmdline.floating", "0"); applyCmdline(cl, app); void syncPrefs(app); app.emit("ui"); });
    grip.addEventListener("mousedown", (e) => {
      const x0 = e.clientX, y0 = e.clientY;
      const fx = Number(ls("archi.cmdline.floatX", "0")), fy = Number(ls("archi.cmdline.floatY", "-16"));
      const mv = (ev: MouseEvent) => { lsSet("archi.cmdline.floatX", String(fx + ev.clientX - x0)); lsSet("archi.cmdline.floatY", String(fy + ev.clientY - y0)); place(); };
      const up = () => { removeEventListener("mousemove", mv); removeEventListener("mouseup", up); };
      addEventListener("mousemove", mv); addEventListener("mouseup", up);
      e.preventDefault();
    });
    cl.el.prepend(grip);
  } else if (!floating && grip) grip.remove();
  const place = () => {
    if (!cl.el.classList.contains("ws-floating")) { cl.el.style.transform = ""; return; }
    cl.el.style.transform = `translate(calc(-50% + ${Number(ls("archi.cmdline.floatX", "0"))}px), ${Number(ls("archi.cmdline.floatY", "-16"))}px)`;
  };
  place();
}

// ---- settings sync with the engine (ui.prefs: defaults of KEYBOARDNAV, LANGUAGE, CMDLINEOPTIONS …) ----
async function syncPrefs(app: App) {
  const values: Record<string, string> = {
    keyboardCursorStep: ls("archi.keyboardCursorStep", "10"), uiLanguage: languageSetting(), systemLanguage: systemLanguage(),
    "cmdline.fontSize": ls("archi.cmdline.fontSize", "11"), "cmdline.lines": ls("archi.cmdline.lines", "4"), "cmdline.opacity": ls("archi.cmdline.opacity", "0.55"),
    "cmdline.floating": ls("archi.cmdline.floating", "0"), fileTabs: ls("archi.fileTabs", "0"), panelTab: app.panelTab,
    crashReports: (await WS.crash("status")).enabled ? "1" : "0",
  };
  await app.tryCall("ui.prefs", { values });
}

// ---- crash reports (CrashReporter.offerPendingReports) ----
async function offerCrashReports() {
  const st = await WS.crash("status");
  if (!st.count) return;
  const text = (await WS.crash("text")).text ?? "";
  const s = new Sheet(440);
  const done = async (discard: boolean) => { s.close(); if (discard) await WS.crash("clear"); };
  s.body.append(h("div", { class: "pb-sheet-head", text: "Oanarina Archi Tool quit unexpectedly" }),
    h("div", { style: { padding: "0 14px 8px" }, text: "A crash report was saved (no drawing contents or file names). Would you like to send it? You can review it first." }),
    h("div", { class: "pb-sheet-foot" },
      button("Discard", { onClick: () => void done(true) }),
      button("Show Report", { onClick: () => { void WS.crash("show"); s.close(); } }),
      button("Copy Report", { onClick: async () => { await WS.crash("copy", text); await done(true); } }),
      button("Open GitHub Issue", { prominent: true, onClick: async () => {
        const url = `${ISSUES}?title=${encodeURIComponent("Crash report")}&body=${encodeURIComponent("```\n" + text.slice(0, 5000) + "\n```")}`;
        const n = (window as any).archi;
        if (n?.openExternal) await n.openExternal(url); else window.open(url, "_blank");
        await done(true);
      } })));
}

async function crashCommand(app: App, op: string) {
  switch (op) {
    case "On": await WS.crash("on"); app.print("Crash reports on: a report is saved if the app quits unexpectedly (nothing is sent automatically)."); break;
    case "Off": await WS.crash("off"); app.print("Crash reports off."); break;
    case "Show": { const st = await WS.crash("show"); app.print(st.count ? `${st.count} crash report(s) in ${st.folder}.` : "No saved crash reports."); break; }
    case "Clear": { const st = await WS.crash("clear"); app.print(`${st.removed ?? 0} crash report(s) removed.`); break; }
    default: { const st = await WS.crash("status"); app.print(`Crash reports ${st.enabled ? "on" : "off"}; ${st.count} saved. ${st.environment}.`); }
  }
}

// ---- settings export / import (SettingsTransfer) ----
function localSettings(): Record<string, string> {
  const out: Record<string, string> = {};
  try { for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i)!; if (k.startsWith("archi.")) out[k] = localStorage.getItem(k) ?? ""; } } catch {}
  return out;
}
async function exportSettings(app: App) {
  const r = await WS.exportSettings(localSettings());
  if (r) app.print(`Settings exported to ${r.path} (${r.count} values).`);
}
async function importSettings(app: App) {
  const r = await WS.importSettings();
  if (!r) return;
  if (r.error) { app.print(r.error); return; }
  for (const [k, v] of Object.entries(r.ui ?? {})) if (k.startsWith("archi.")) lsSet(k, String(v));
  app.print(`Imported ${r.count ?? 0} setting(s). Restart the app to apply all of them.`);
}

export function installWorkspace(app: App, hooks: WorkspaceHooks) {
  planHooks.current = hooks.plan;
  const fileTabs = new FileTabs(app);
  const tiles = new TiledViews(app, { plan: hooks.plan.el, view3d: hooks.view3d, ensure3D: hooks.ensure3D, changed: () => { if (app.mode === "Split") hooks.relayout(); } });
  (window as any).archiWorkspace = { floatPanel: (t: string) => floatPanel(app, t), floatingWindow, tiles, tileState, fileTabs, showOutliner: () => showOutliner(app), showAssistant: (q?: string) => showAssistant(app, q), progress, WS };

  // Slow engine calls show in the status bar; Cancel sends Escape.
  trackEngine(app.engine, () => (app.prompt.command ? `Running ${app.prompt.command}` : "Working…"), () => void app.cancel());

  // The drawing window's state for the file tabs of every window.
  const report = () => {
    const i = app.info;
    const summary = `${i?.path ?? "Not saved yet"}\n${i?.entities ?? 0} drafting object(s), ${i?.elements ?? 0} building element(s), ${i?.layouts?.length ?? 0} sheet(s), ${i?.levels?.length ?? 0} level(s)${i?.dirty ? "\nUnsaved changes" : ""}`;
    WS.setState({ title: i?.title ?? "Untitled", path: i?.path ?? null, dirty: !!i?.dirty, summary });
  };
  app.on("doc", report);
  app.on(["drawing", "doc"], () => invalidateNavigator());

  // FLOATPANEL with a two-word panel ("Quick Props") from the menus: the shell floats it directly.
  const run = app.runCommand.bind(app);
  app.runCommand = async (line: string) => {
    const m = /^\s*FLOATPANEL\s+(.+?)\s*$/i.exec(line);
    const tab = m ? PANEL_TABS.find((t) => t.toLowerCase() === m[1].toLowerCase()) : undefined;
    if (tab && /\s/.test(tab)) { app.print(`Command: FLOATPANEL`); floatPanel(app, tab); return; }
    return run(line);
  };
  document.addEventListener("archi:floatPanel", (e) => floatPanel(app, String((e as CustomEvent).detail)));
  app.on("ui", () => void app.tryCall("ui.prefs", { values: { panelTab: app.panelTab } }));

  const prevHost = app.uiHooks.host;
  app.uiHooks.host = (p: any) => {
    switch (p?.action) {
      case "showPanel": {
        const tab = PANEL_TABS.find((t) => t.toLowerCase() === String(p.panel ?? "").toLowerCase());
        if (p.mode === "2D" && app.mode !== "2D" && app.mode !== "Split") { app.activeLayout = 0; app.setUI("mode", "2D"); }
        if (tab && isFloating(tab)) { floatPanel(app, tab); return true; } // StudioPanelsDock.show
        break;
      }
      case "floatPanel": { const tab = PANEL_TABS.find((t) => t.toLowerCase() === String(p.panel ?? "").toLowerCase()); if (tab) floatPanel(app, tab); return true; }
      case "tiledViews": {
        const k = String(p.arrangement ?? "4");
        if (k === "Single") { app.setUI("mode", "2D"); return true; }
        tileState.arrangement = arrangementFor(k);
        if (app.mode === "Split") hooks.relayout(); else app.setUI("mode", "Split");
        app.print(`Tiled views: ${arrangementTitle()} — ${tileState.kinds.slice(0, tileState.count()).join(", ")}`);
        return true;
      }
      case "dialog":
        if (p.dialog === "outliner") { showOutliner(app); return true; }
        if (p.dialog === "assistant") { showAssistant(app, p.ask ? String(p.ask) : undefined); return true; }
        break;
      case "preference":
        if (p.key === "keyboardCursorStep") { lsSet("archi.keyboardCursorStep", String(p.value)); return true; }
        if (p.key === "uiLanguage") { setLanguageSetting(String(p.value)); document.dispatchEvent(new Event("archi:language")); app.emit("ui"); return true; }
        if (p.key === "cmdline" && p.value) {
          const v = p.value;
          if (v.reset) for (const k of ["fontSize", "lines", "opacity", "floating", "floatX", "floatY"]) { try { localStorage.removeItem("archi.cmdline." + k); } catch {} }
          else { lsSet("archi.cmdline.fontSize", String(v.fontSize)); lsSet("archi.cmdline.lines", String(v.lines)); lsSet("archi.cmdline.opacity", String(v.opacity)); lsSet("archi.cmdline.floating", v.floating ? "1" : "0"); }
          applyCmdline(hooks.commandLine, app); app.emit("ui");
          return true;
        }
        break;
      case "exportSettings": void exportSettings(app); return true;
      case "importSettings": void importSettings(app); return true;
      case "crashReports": void crashCommand(app, String(p.op ?? "Status")); return true;
      case "fileTabs": fileTabs.visible = !!p.on; return true;
      case "windowTabs": void WS.windowTabs(String(p.op ?? "Merge")).then(() => { if (p.op !== "Windows") fileTabs.visible = true; }); return true;
      case "arrangeWindows": void WS.arrange(String(p.mode ?? "Vertical")).then((n) => { if (p.mode === "Tabs") fileTabs.visible = true; app.print(n ? `${n} window(s) arranged: ${String(p.mode ?? "Vertical").toLowerCase()}.` : "No document windows."); }); return true;
      case "fullScreen": void WS.fullScreen(); return true;
      case "quickProps": { const r = !!prevHost?.(p); document.dispatchEvent(new Event("archi:quickprops")); return r; }
    }
    return !!prevHost?.(p);
  };

  // `engineExit`: an opted-in crash report for the engine process.
  (app.engine as any).onNotify?.((n: any) => { if (n?.method === "engineExit") void WS.crash("report", String(n.params?.message ?? "")); });

  installKeyboardCrosshair(app, hooks.plan);
  applyCmdline(hooks.commandLine, app);
  document.addEventListener("archi:ready", () => { void syncPrefs(app); restoreFloatingPanels(app); void offerCrashReports(); report(); }, { once: true });
  return { fileTabs, tiles, languages: LANGUAGES, resolvedLanguage, showMenu };
}
