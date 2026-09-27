// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Installs the dialogs and UI-layer commands of part A of the port: Settings (OPTIONS), Drawing Units, Drafting
// Settings, Quick Select, Layer States, Layers panel filters, Page Setup, workspaces, ribbon customisation, custom
// keyboard shortcuts, templates, autosave and the startup script. The engine's portable UI commands ask for them with
// `host` notifications (docs/ENGINE-PROTOCOL.md "Dialogs"); ribbon items with a Mac `ui` target open them directly.
import type { App } from "../app";
import type { MenuItem } from "../ui/menu";
import { prefs, applyTheme } from "../prefs";
import { ctx, folders, syncEnginePrefs, scriptsFolder } from "./context";
import { openSettings, applyDraftHere } from "./preferences";
import { openUnits, openDraftingSettings } from "./units";
import { openQuickSelect } from "./quickselect";
import { openLayerStates } from "./layerstates";
import { openPageSetup, pageSetupHooks } from "./pagesetup";
import { openCUI, setCustomization, decodeCustomization, panelSymbol } from "./cui";
import { openShortcutsReference, dispatchShortcut } from "./shortcuts";
import { applyWorkspaceNamed, saveWorkspace, workspaceMenu } from "./workspaces";
import { newFromTemplate, templateMenu, revealTemplatesFolder, listTemplates, openTemplateFile, DrawingTemplate } from "./templates";
import { requestLayerFilter, renderLayersPanel } from "./layers-panel";
import { reveal } from "./context";

export { openSettings, openUnits, openDraftingSettings, openQuickSelect, openLayerStates, openPageSetup, openCUI, openShortcutsReference, newFromTemplate, openTemplateFile, revealTemplatesFolder, renderLayersPanel, listTemplates };
export type { DrawingTemplate };

/** Page setup of the active sheet (Sheet mode) or of model space, as the Mac PAGESETUP does. */
export function openPageSetupForView() {
  const a = ctx.app!;
  return openPageSetup(a.mode === "Sheet" && a.activeLayout > 0 ? a.activeLayout - 1 : null);
}

/** Opens the dialog behind a Mac `ui` target (ribbon items: "sheet:units", "window:PreferencesWindow" …) or an "@ui:" action. */
export function openUI(ref: string): boolean {
  switch (ref) {
    case "window:PreferencesWindow": openSettings(); return true;
    case "window:PreferencesWindow.shortcuts": openSettings("Shortcuts"); return true;
    case "window:keyboard-shortcuts": openShortcutsReference(); return true;
    case "window:CUIWindow": openCUI(); return true;
    case "sheet:units": void openUnits(); return true;
    case "sheet:drafting": void openDraftingSettings(); return true;
    case "sheet:quickSelect": void openQuickSelect(); return true;
    case "sheet:layerStates": void openLayerStates(); return true;
    case "sheet:pageSetup": void openPageSetupForView(); return true;
    case "FileManager.default.createDirectory": void revealTemplatesFolder(); return true;
    case "ScriptLibrary.revealFolder": void scriptsFolder().then(reveal); return true;
  }
  return false;
}

/** Engine `host` notifications for dialogs and application settings. True when handled. */
export function handleHost(p: any): boolean {
  const a = ctx.app!;
  switch (p.action) {
    case "dialog":
      switch (String(p.dialog)) {
        case "options": openSettings(p.tab); return true;
        case "quickSelect": void openQuickSelect(); return true;
        case "layerStates": void openLayerStates(); return true;
        case "pageSetup": void openPageSetupForView(); return true;
        case "cui": openCUI(); return true;
        case "units": void openUnits(); return true;
        case "drafting": void openDraftingSettings(); return true;
      }
      return false;
    case "showPanel": {
      // FileController.showPanel: panel names that are dialogs on the Mac.
      const n = String(p.panel ?? "").toLowerCase().replace(/[ -]/g, "");
      if (n === "units") { void openUnits(); return true; }
      if (["drafting", "dsettings", "settings", "draftingsettings"].includes(n)) { void openDraftingSettings(); return true; }
      if (n === "options" || n === "preferences") { openSettings(); return true; }
      if (n === "quickselect" || n === "qselect") { void openQuickSelect(); return true; }
      if (n === "layerstates" || n === "layerstate") { void openLayerStates(); return true; }
      if (n === "pagesetup") { void openPageSetupForView(); return true; }
      return false;
    }
    case "preference": {
      const k = String(p.key);
      if (k === "cursorSize" || k === "autosaveMinutes") prefs.set(k, Number(p.value));
      else if (k === "theme") prefs.set("theme", String(p.value) === "light" ? "light" : "dark");
      return true;
    }
    case "workspace": if (!applyWorkspaceNamed(String(p.name ?? ""))) a.print(`Workspace "${p.name}" not found.`); return true;
    case "workspaceSave": saveWorkspace(String(p.name ?? "").trim() || prefs.get("workspaceCurrent")); return true;
    case "cui":
      if (p.op === "set" && p.data) {
        try { setCustomization(decodeCustomization(JSON.stringify(p.data))); } catch (e: any) { a.print(e?.message ?? String(e)); }
        if (Array.isArray(p.quickAccess) && p.quickAccess.length) prefs.set("quickAccess", p.quickAccess.map(String));
      }
      return true;
    case "layerFilter":
      requestLayerFilter(String(p.filter ?? ""));
      a.showPanels = true; a.setUI("panelTab", "Layers"); a.emit("panel");
      return true;
    case "newWindow":
      if (p.kind === "template" && p.path) {
        if (a.engine.native) void a.engine.native.newWindow({ kind: "template", path: String(p.path) });
        else void newFromTemplate(String(p.path), true);
        return true;
      }
      return false;
  }
  return false;
}

// ---- ribbon hooks (ui/ribbon.ts) ----
export interface RibbonPanelItem { title: string; symbol: string; command: string; args?: string; size: "large" | "small"; kind: "command" }
/** Custom panels of a ribbon tab (CustomRibbonPanels), appended after the built-in panels. */
export function customRibbonPanels(tab: string, titleFor: (name: string) => string | undefined): { name: string; items: RibbonPanelItem[] }[] {
  return prefs.ribbon.panels.filter((p) => p.tab === tab).map((p) => ({
    name: p.title,
    items: p.commands.map((line) => {
      const [cmd, ...rest] = line.split(" ");
      const name = cmd.toUpperCase();
      const title = titleFor(name) ?? (name[0] + name.slice(1).toLowerCase());
      return { title, symbol: panelSymbol(p, line), command: cmd, args: rest.join(" ") || undefined, size: p.commands.length > 4 ? "small" : "large", kind: "command" as const };
    }),
  }));
}
export function isHiddenRibbonPanel(title: string) { return prefs.ribbon.hiddenPanels.includes(title); }
/** Dynamic ribbon menu entries ("{Workspaces.all}"). */
export function dynamicMenu(kind: string): MenuItem[] | null {
  if (kind === "Workspaces.all") return workspaceMenu().filter((m) => !m.separator && m.title !== "Save Current Workspace…");
  return null;
}

// ---- menu bar additions (ui/titlebar.ts) ----
let templateItems: MenuItem[] = [];
export function newFromTemplateMenu(): MenuItem[] { if (ctx.app) void templateMenu().then((t) => { templateItems = t; }); return templateItems.length ? templateItems : [{ title: "Loading…", disabled: true }]; }
export { workspaceMenu };

// ---- keyboard ----
/** Custom shortcuts first (ShortcutDispatcher), then Ctrl+, (Settings) and Ctrl+Shift+P (Page Setup). */
export function handleDialogKey(e: KeyboardEvent): boolean {
  if (dispatchShortcut(e)) return true;
  const ctrl = e.ctrlKey || e.metaKey;
  if (ctrl && !e.altKey && e.key === ",") { e.preventDefault(); openSettings(); return true; }
  if (ctrl && e.shiftKey && !e.altKey && (e.key === "P" || e.key === "p")) { e.preventDefault(); void openPageSetupForView(); return true; }
  return false;
}

// ---- autosave (AutosaveManager): unsaved changes go to a recovery file every N minutes ----
const session = Math.random().toString(36).slice(2, 8);
let lastAutosave = Date.now();
let recoveryPath: string | null = null;
async function autosaveTick() {
  const a = ctx.app!;
  const minutes = prefs.get("autosaveMinutes");
  if (!minutes || !a.info?.dirty || Date.now() - lastAutosave < minutes * 60000) return;
  lastAutosave = Date.now();
  const f = await folders();
  const safe = (a.info.title || "Untitled").replace(/[\\/:*?"<>|]/g, "-");
  const path = `${f.recovery}\\${safe} (recovered ${session}).archi`;
  const r = await a.tryCall("file.export", { path, format: "archi" });
  if (r) recoveryPath = path;
}
async function dropRecovery() {
  const n = ctx.app?.engine.native;
  if (recoveryPath && n?.removeFile) { await n.removeFile(recoveryPath); recoveryPath = null; }
}

// ---- startup.js from the script library ----
async function runStartupScript() {
  const a = ctx.app!;
  const n = a.engine.native;
  if (!prefs.get("runStartupScript") || !n?.readTextFile) return;
  const src = await n.readTextFile(`${await scriptsFolder()}\\startup.js`);
  if (!src) return;
  const archi = { run: (line: string) => a.runCommand(line), call: (m: string, p?: unknown) => a.engine.call(m, p ?? {}), print: (s: unknown) => a.print(String(s)), get selection() { return a.selection.ids; } };
  try { await new Function("archi", `return (async () => { ${src}\n })()`)(archi); } catch (e: any) { a.print(`startup.js: ${e?.message ?? e}`); }
}

export function installDialogs(app: App, opts: { displayBox?: () => number[] | null } = {}) {
  ctx.app = app;
  applyTheme();
  if (opts.displayBox) pageSetupHooks.displayBox = opts.displayBox;
  app.uiHooks = {
    host: (p) => handleHost(p),
    ui: (ref) => openUI(ref),
    newTemplate: (t) => (t === "metric" && ["inches", "feet"].includes(prefs.get("defaultUnits")) ? "imperial" : t),
    afterNew: async (t) => {
      const units = t === "metric" && !["inches", "feet"].includes(prefs.get("defaultUnits")) ? prefs.get("defaultUnits") : undefined;
      await app.tryCall("drafting.defaults", { ...(units ? { units } : {}), draft: prefs.get("draft") });
    },
  };
  prefs.on(() => { app.canvas?.refresh(); app.emit("ui"); });
  let synced = false;
  app.on("doc", () => {
    if (!synced) { synced = true; void syncEnginePrefs(); void folders().then(() => templateMenu().then((t) => { templateItems = t; })); }
    if (app.info && !app.info.dirty) void dropRecovery();
  });
  addEventListener("storage", (e) => { if (e.key === "archi.broadcast.applyDraft") void applyDraftHere(); });
  setInterval(() => void autosaveTick(), 30000);
  addEventListener("beforeunload", () => { void dropRecovery(); });
  document.addEventListener("archi:ready", () => { void syncEnginePrefs(); void runStartupScript(); }, { once: true });
}
