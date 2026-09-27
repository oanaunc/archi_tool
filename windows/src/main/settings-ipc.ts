// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Native services behind the Settings dialog and the other preference-driven dialogs: standard folders (templates,
// script library, recovery), reveal/choose folders, text files for shortcut and ribbon customisation export/import,
// and the few settings the main process needs itself (recent-documents limit, crash reports) kept in settings.json.
import { app, ipcMain, dialog, shell, BrowserWindow, crashReporter } from "electron";
import path from "node:path";
import fs from "node:fs";

const settingsFile = () => path.join(app.getPath("userData"), "settings.json");
export function readSettings(): Record<string, unknown> { try { return JSON.parse(fs.readFileSync(settingsFile(), "utf8")); } catch { return {}; } }
function writeSettings(s: Record<string, unknown>) { fs.mkdirSync(path.dirname(settingsFile()), { recursive: true }); fs.writeFileSync(settingsFile(), JSON.stringify(s, null, 1)); }
/** Settings ▸ General ▸ Recent files: "Remember N documents" (1–50, default 12). */
export function recentLimit(): number { const n = Number(readSettings().recentLimit); return Number.isFinite(n) && n >= 1 ? Math.min(50, Math.round(n)) : 12; }

export function appFolders() {
  const data = app.getPath("userData");
  return {
    userData: data, documents: app.getPath("documents"), home: app.getPath("home"), desktop: app.getPath("desktop"),
    templates: path.join(data, "Templates"), scripts: path.join(data, "Scripts"), recovery: path.join(data, "Recovery"),
  };
}

let registered = false;
export function registerSettingsIpc() {
  if (registered) return;
  registered = true;
  // Crash reports stay on this computer (Settings ▸ General ▸ Crash reports, off by default).
  try { if (readSettings().crashReports === true) crashReporter.start({ uploadToServer: false }); } catch {}
  ipcMain.handle("settings:paths", () => appFolders());
  ipcMain.handle("settings:set", (_e, key: string, value: unknown) => { const s = readSettings(); s[key] = value; writeSettings(s); });
  ipcMain.handle("shell:revealPath", async (_e, p: string, create = true) => {
    if (!p) return;
    try { if (create && !path.extname(p)) fs.mkdirSync(p, { recursive: true }); } catch {}
    if (fs.existsSync(p) && fs.statSync(p).isDirectory()) await shell.openPath(p); else shell.showItemInFolder(p);
  });
  ipcMain.handle("dialog:folder", async (e, opts: { title?: string; defaultPath?: string }) => {
    const win = BrowserWindow.fromWebContents(e.sender)!;
    const r = await dialog.showOpenDialog(win, { title: opts?.title, defaultPath: opts?.defaultPath, properties: ["openDirectory", "createDirectory"] });
    return r.canceled ? null : r.filePaths[0];
  });
  ipcMain.handle("fs:readText", (_e, p: string) => { try { return fs.readFileSync(p, "utf8"); } catch { return null; } });
  ipcMain.handle("fs:writeText", (_e, p: string, text: string) => { try { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, text); return true; } catch { return false; } });
  ipcMain.handle("fs:remove", (_e, p: string) => { try { fs.rmSync(p, { force: true }); } catch {} });
}
