// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Workspaces (WSCURRENT / WSSAVE, ArchiApp/Workspaces.swift): a saved arrangement of the window — view mode, panels,
// panel tab, script console, ribbon tab and collapsed state, clean screen. Built-in workspaces plus the user's own.
import type { MenuItem } from "../ui/menu";
import { prefs, WorkspaceLayout } from "../prefs";
import { app, syncEnginePrefs } from "./context";

export function captureWorkspace(name: string): WorkspaceLayout {
  const a = app();
  return { name, mode: a.mode, showPanels: a.showPanels, panelTab: a.panelTab, showScriptConsole: a.showScriptConsole, ribbonTab: a.ribbonTab, ribbonCollapsed: a.ribbonCollapsed, cleanScreen: a.cleanScreen };
}

/** Workspaces.apply: panels, views and ribbon change at once. */
export function applyWorkspace(w: WorkspaceLayout) {
  const a = app();
  const mode = (["2D", "3D", "Split", "Sheet"].includes(w.mode) ? w.mode : ({ plan: "2D", model: "3D", split: "Split", sheet: "Sheet" } as Record<string, string>)[w.mode.toLowerCase()] ?? "2D") as any;
  if (mode === "Sheet" && a.activeLayout === 0 && a.info?.layouts.length) a.activeLayout = 1;
  if (mode !== "Sheet") a.activeLayout = 0;
  a.showScriptConsole = w.showScriptConsole;
  a.cleanScreen = w.cleanScreen;
  a.setUI("showPanels", w.showPanels);
  a.setUI("panelTab", w.panelTab);
  a.setUI("ribbonTab", w.ribbonTab);
  a.setUI("ribbonCollapsed", w.ribbonCollapsed);
  a.setUI("mode", mode);
  prefs.set("workspaceCurrent", w.name);
  a.emit("panel");
}

export function applyWorkspaceNamed(name: string): boolean {
  const w = prefs.findWorkspace(name);
  if (!w) return false;
  applyWorkspace(w);
  return true;
}

export function saveWorkspace(name: string) {
  prefs.saveWorkspace(captureWorkspace(name));
  void syncEnginePrefs();
}

/** View ▸ Workspace menu: every workspace (current one checked) and "Save Current Workspace…" (WSSAVE). */
export function workspaceMenu(): MenuItem[] {
  const cur = prefs.get("workspaceCurrent");
  return [
    ...prefs.workspaces.map((w) => ({ title: w.name, checked: w.name === cur, action: () => applyWorkspace(w) })),
    { separator: true },
    { title: "Save Current Workspace…", action: () => void app().runCommand("WSSAVE") },
  ];
}
