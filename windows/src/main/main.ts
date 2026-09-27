// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Electron main process: one BrowserWindow per document, each with its own archi-engine process.
import { app, BrowserWindow, ipcMain, dialog, shell, protocol, net, Menu } from "electron";
import path from "node:path";
import fs from "node:fs";
import { pathToFileURL } from "node:url";
import { EngineProcess } from "./rpc";

interface DocRequest { kind: string; path?: string }
const windows = new Map<number, { win: BrowserWindow; engine: EngineProcess | null; request: DocRequest | null }>();

function resourcesDir(): string {
  return app.isPackaged ? process.resourcesPath : path.resolve(__dirname, "../../resources");
}
function enginePath(): string {
  if (process.env.ARCHI_ENGINE) return process.env.ARCHI_ENGINE;
  const exe = process.platform === "win32" ? "archi-engine.exe" : "archi-engine";
  return path.join(resourcesDir(), "engine", exe);
}
const recentFile = () => path.join(app.getPath("userData"), "recent.json");
function readRecent(): string[] { try { return JSON.parse(fs.readFileSync(recentFile(), "utf8")); } catch { return []; } }
function writeRecent(list: string[]) { fs.mkdirSync(path.dirname(recentFile()), { recursive: true }); fs.writeFileSync(recentFile(), JSON.stringify(list.slice(0, 12))); }

/** Copies a bundled sample (with its textures) to Documents\Oanarina Archi Tool\Samples so it can be edited and saved (like the Mac app). */
function prepareSample(name: string): string | null {
  const src = path.join(resourcesDir(), "samples");
  const file = path.join(src, name + ".archi");
  if (!fs.existsSync(file)) return null;
  const dest = path.join(app.getPath("documents"), "Oanarina Archi Tool", "Samples");
  try {
    fs.mkdirSync(path.join(dest, "textures"), { recursive: true });
    const tex = path.join(src, "textures");
    if (fs.existsSync(tex)) for (const t of fs.readdirSync(tex)) { const to = path.join(dest, "textures", t); if (!fs.existsSync(to)) fs.copyFileSync(path.join(tex, t), to); }
    const out = path.join(dest, name + ".archi");
    if (!fs.existsSync(out)) fs.copyFileSync(file, out);
    return out;
  } catch { return file; }
}

function createWindow(request: DocRequest | null = { kind: "start" }): BrowserWindow {
  const win = new BrowserWindow({
    width: 1440, height: 900, minWidth: 600, minHeight: 480,
    frame: false, backgroundColor: "#26272B", show: false,
    title: "Oanarina Archi Tool",
    icon: path.join(resourcesDir(), "icon.ico"),
    webPreferences: { preload: path.join(__dirname, "../preload/preload.js"), contextIsolation: true, sandbox: false, nodeIntegration: false, spellcheck: false },
  });
  const id = win.webContents.id;
  let engine: EngineProcess | null = new EngineProcess(enginePath(), ["--cwd", app.getPath("documents")], path.dirname(enginePath()));
  const entry = { win, engine, request };
  windows.set(id, entry);
  engine.on("notification", (n) => { if (!win.isDestroyed()) win.webContents.send("engine:notify", n); });
  engine.on("stderr", (s: string) => { if (!win.isDestroyed()) win.webContents.send("engine:notify", { method: "log", params: { text: s.trim(), stderr: true } }); });
  engine.on("exit", (message: string) => { if (!win.isDestroyed()) win.webContents.send("engine:notify", { method: "engineExit", params: { message } }); });
  try { engine.start(); } catch (e: any) { entry.engine = null; engine = null; }
  const sendState = () => { if (!win.isDestroyed()) win.webContents.send("window:state", { maximized: win.isMaximized(), focused: win.isFocused() }); };
  for (const ev of ["maximize", "unmaximize", "focus", "blur", "enter-full-screen", "leave-full-screen"] as const) win.on(ev as any, sendState);
  win.once("ready-to-show", () => { win.show(); });
  win.on("closed", () => { entry.engine?.stop(); windows.delete(id); });
  win.loadFile(path.join(__dirname, "../renderer/index.html"));
  return win;
}

function entryFor(e: Electron.IpcMainInvokeEvent) { return windows.get(e.sender.id); }

ipcMain.handle("engine:rpc", async (e, method: string, params: unknown) => {
  const w = entryFor(e);
  if (!w?.engine) throw new Error(JSON.stringify({ code: -32000, message: `archi-engine is not available (${enginePath()}).` }));
  try { return await w.engine.call(method, params); }
  catch (err: any) { throw new Error(JSON.stringify(err && err.code !== undefined ? err : { code: -32603, message: String(err?.message ?? err) })); }
});
ipcMain.handle("window:control", (e, action: string) => {
  const win = BrowserWindow.fromWebContents(e.sender);
  if (!win) return false;
  if (action === "minimize") win.minimize();
  else if (action === "maximize") win.isMaximized() ? win.unmaximize() : win.maximize();
  else if (action === "close") win.close();
  return win.isMaximized();
});
ipcMain.handle("dialog:open", async (e, opts) => {
  const win = BrowserWindow.fromWebContents(e.sender)!;
  const r = await dialog.showOpenDialog(win, { title: opts?.title, properties: ["openFile"], filters: opts?.filters });
  return r.canceled ? null : r.filePaths[0];
});
ipcMain.handle("dialog:save", async (e, opts) => {
  const win = BrowserWindow.fromWebContents(e.sender)!;
  const r = await dialog.showSaveDialog(win, { title: opts?.title, defaultPath: opts?.defaultPath, filters: opts?.filters });
  return r.canceled ? null : r.filePath;
});
ipcMain.handle("recent:list", () => readRecent().filter((p) => fs.existsSync(p)).map((p) => ({ path: p, modified: fs.statSync(p).mtimeMs })));
ipcMain.handle("recent:add", (_e, p: string) => { writeRecent([p, ...readRecent().filter((x) => x.toLowerCase() !== p.toLowerCase())]); app.addRecentDocument(p); });
ipcMain.handle("recent:clear", () => { writeRecent([]); app.clearRecentDocuments(); });
ipcMain.handle("sample:path", (_e, name: string) => prepareSample(name));
ipcMain.handle("window:new", (_e, req: DocRequest | undefined) => { createWindow(req ?? { kind: "start" }); });
ipcMain.handle("window:request", (e) => entryFor(e)?.request ?? null);
ipcMain.handle("shell:openExternal", (_e, url: string) => { if (/^https:\/\//.test(url)) shell.openExternal(url); });
ipcMain.on("window:title", (e, title: string) => { const win = BrowserWindow.fromWebContents(e.sender); if (win) win.setTitle(title); });

protocol.registerSchemesAsPrivileged([{ scheme: "archi-file", privileges: { standard: false, secure: true, supportFetchAPI: true, stream: true } }]);

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) app.quit();
else {
  app.on("second-instance", (_e, argv) => {
    const file = argv.slice(1).find((a) => /\.(archi|dxf|dwg|ifc)$/i.test(a));
    createWindow(file ? { kind: "open", path: file } : { kind: "start" });
  });
  app.whenReady().then(() => {
    Menu.setApplicationMenu(null);
    // Images referenced by drawings (raster images, textures) are served read-only from disk.
    protocol.handle("archi-file", (req) => net.fetch(pathToFileURL(decodeURIComponent(req.url.slice("archi-file://".length))).toString()));
    const file = process.argv.slice(1).find((a) => /\.(archi|dxf|dwg|ifc)$/i.test(a));
    createWindow(file ? { kind: "open", path: file } : { kind: "start" });
  });
  app.on("window-all-closed", () => app.quit());
}
