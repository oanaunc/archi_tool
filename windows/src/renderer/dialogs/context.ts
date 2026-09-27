// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Shared state of the dialogs: the window model, the app folders (templates, script library, recovery — the
// FileLocations of ArchiApp/AppFeatures.swift), and the preferences the engine's portable UI commands read as prompt
// defaults (ui.prefs: CURSORSIZE, SAVETIME, THEME, WSCURRENT, WSSAVE, CUI, NEWFROMTEMPLATE, SAVEASTEMPLATE).
import type { App } from "../app";
import { prefs } from "../prefs";

export interface Folders { userData: string; documents: string; home: string; desktop: string; templates: string; scripts: string; recovery: string }

export const ctx: { app: App | null } = { app: null };
export function app(): App { if (!ctx.app) throw new Error("dialogs not installed"); return ctx.app; }

let folderCache: Folders | null = null;
/** Standard folders from the Electron main process, or placeholders in the browser test page. */
export async function folders(): Promise<Folders> {
  if (folderCache) return folderCache;
  const n = ctx.app?.engine.native;
  const f = n?.paths ? await n.paths().catch(() => null) : null;
  folderCache = f ?? {
    userData: "%APPDATA%\\Oanarina Archi Tool", documents: "Documents", home: "~", desktop: "Desktop",
    templates: "%APPDATA%\\Oanarina Archi Tool\\Templates", scripts: "%APPDATA%\\Oanarina Archi Tool\\Scripts", recovery: "%APPDATA%\\Oanarina Archi Tool\\Recovery",
  };
  return folderCache;
}
export function cachedFolders(): Folders | null { return folderCache; }
/** FileLocations.templates: Settings ▸ General ▸ File locations ▸ Templates, else the default folder. */
export async function templatesFolder(): Promise<string> { return prefs.get("templatesFolder") || (await folders()).templates; }
export async function scriptsFolder(): Promise<string> { return prefs.get("scriptsFolder") || (await folders()).scripts; }

/** Home folder written as ~ (FolderRow shows paths with NSHomeDirectory() replaced). */
export function tilde(p: string): string {
  const h = folderCache?.home;
  return h && p.toLowerCase().startsWith(h.toLowerCase()) ? "~" + p.slice(h.length) : p;
}

/** Opens a folder in Explorer (created first), like NSWorkspace.activateFileViewerSelecting. */
export async function reveal(path: string) {
  const n = ctx.app?.engine.native;
  if (n?.revealPath) await n.revealPath(path);
  else ctx.app?.print(`Folder: ${path}`);
}

/** Sends the preferences the engine's portable commands use as prompt defaults. */
export async function syncEnginePrefs() {
  const a = ctx.app;
  if (!a) return;
  const values = {
    cursorSize: String(prefs.cursorSize), autosaveMinutes: String(prefs.get("autosaveMinutes")), theme: prefs.get("theme"),
    templatesFolder: await templatesFolder(), workspaces: prefs.workspaces.map((w) => w.name).join("|"), workspace: prefs.get("workspaceCurrent"),
    cui: JSON.stringify(prefs.ribbon), quickAccess: prefs.quickAccess.join(","),
  };
  await a.tryCall("ui.prefs", { values });
}
