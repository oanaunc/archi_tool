// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Main-process services of the workspace module (renderer/workspace/): the list of open drawing windows for the file
// tab bar (FileTabs, AppNavigationViews.swift), window arrangement (SYSWINDOWS, WindowArrangement in
// AppCommandsRound9.swift) and window tabs (WINDOWTABS: Merge / Tabs / Windows — Windows has no native window tabs, so
// merged windows share one frame and the file tab bar switches between them), settings export / import
// (EXPORTSETTINGS / IMPORTSETTINGS, SettingsTransfer), opt-in crash reports (CRASHREPORTS, CrashReporter.swift: text
// reports in %APPDATA%\Oanarina Archi Tool\Logs, never sent automatically) and the AI assistant's HTTP requests and API
// key (Assistant.swift; the key is encrypted with Windows DPAPI through safeStorage, never stored in the drawing).
import { app, BrowserWindow, ipcMain, dialog, screen, shell, safeStorage, clipboard } from "electron";
import path from "node:path";
import fs from "node:fs";
import os from "node:os";
import { readSettings } from "./settings-ipc";

interface DocState { title: string; path: string | null; dirty: boolean; summary?: string }
const states = new Map<number, DocState>();
/** Windows merged into one tab group (WINDOWTABS Merge / SYSWINDOWS Tabs). */
const tabbed = new Set<number>();

const settingsFile = () => path.join(app.getPath("userData"), "settings.json");
function setSetting(key: string, value: unknown) {
  const s = readSettings();
  s[key] = value;
  fs.mkdirSync(path.dirname(settingsFile()), { recursive: true });
  fs.writeFileSync(settingsFile(), JSON.stringify(s, null, 1));
}

function docWindows(): BrowserWindow[] { return BrowserWindow.getAllWindows().filter((w) => !w.isDestroyed() && states.has(w.webContents.id)); }
function list() {
  const focused = BrowserWindow.getFocusedWindow();
  return docWindows().map((w) => ({ id: w.webContents.id, ...states.get(w.webContents.id)!, focused: w === focused, tabbed: tabbed.has(w.webContents.id) }));
}
function broadcast() {
  const l = list();
  for (const w of docWindows()) w.webContents.send("ws:windows", l);
}
function byId(id: number) { return docWindows().find((w) => w.webContents.id === id) ?? null; }

/** Frames of n windows in a work area (WindowArrangement.frames): side by side, stacked or cascaded. */
export function arrangeFrames(n: number, r: { x: number; y: number; width: number; height: number }, mode: string) {
  const out: { x: number; y: number; width: number; height: number }[] = [];
  if (n <= 0) return out;
  if (mode === "Vertical") {
    const w = Math.floor(r.width / n);
    for (let i = 0; i < n; i++) out.push({ x: r.x + i * w, y: r.y, width: w, height: r.height });
  } else if (mode === "Horizontal") {
    const hh = Math.floor(r.height / n);
    for (let i = 0; i < n; i++) out.push({ x: r.x, y: r.y + i * hh, width: r.width, height: hh });
  } else {
    const step = 28;
    const w = Math.round(Math.max(r.width - step * (n - 1), r.width * 0.6)), hh = Math.round(Math.max(r.height - step * (n - 1), r.height * 0.6));
    for (let i = 0; i < n; i++) out.push({ x: r.x + i * step, y: r.y + i * step, width: w, height: hh });
  }
  return out;
}

function mergeTabs(anchor: BrowserWindow | null) {
  const wins = docWindows();
  const a = anchor ?? wins[0];
  if (!a) return 0;
  const b = a.getBounds();
  for (const w of wins) {
    tabbed.add(w.webContents.id);
    if (w === a) continue;
    if (w.isFullScreen()) w.setFullScreen(false);
    if (a.isMaximized()) w.maximize(); else w.setBounds(b);
  }
  a.focus();
  broadcast();
  return wins.length;
}

function arrange(mode: string, from: BrowserWindow | null) {
  const wins = docWindows();
  if (!wins.length) return 0;
  if (mode === "Tabs") return mergeTabs(from);
  tabbed.clear();
  const area = screen.getDisplayMatching((from ?? wins[0]).getBounds()).workArea;
  const frames = arrangeFrames(wins.length, area, mode === "Separate" ? "Cascade" : mode);
  wins.forEach((w, i) => { if (w.isFullScreen()) w.setFullScreen(false); if (w.isMaximized()) w.unmaximize(); w.setBounds(frames[i]); w.showInactive(); });
  (from ?? wins[0]).focus();
  broadcast();
  return wins.length;
}

// ---- crash reports ----
const logsFolder = () => path.join(app.getPath("userData"), "Logs");
const crashOn = () => readSettings().crashReports === true;
function environment() { return `Oanarina Archi Tool ${app.getVersion()}, Windows ${os.release()}, ${process.arch}, Electron ${process.versions.electron}`; }
/** Removes the user folder and anything that looks like a drawing or image file name (CrashReporter.redact). */
export function redact(s: string) {
  let t = s.split(os.homedir()).join("~");
  t = t.replace(/([A-Za-z]:)?([\\/][^\s\\/]+)+[\\/][^\s\\/]+\.(archi|dxf|dwg|ifc|pdf|png|jpg|obj|skp|3dm)/gi, "<file>");
  return t;
}
function writeReport(kind: string, detail: string) {
  if (!crashOn()) return;
  try {
    fs.mkdirSync(logsFolder(), { recursive: true });
    const f = path.join(logsFolder(), `crash-${process.pid}-${Date.now()}.log`);
    fs.writeFileSync(f, `Crash report\n${environment()}\n${kind}\n${redact(detail)}\n`, { mode: 0o600 });
  } catch {}
}
function pendingReports(): string[] {
  try { return fs.readdirSync(logsFolder()).filter((f) => /^crash-.*\.log$/.test(f)).map((f) => path.join(logsFolder(), f)).filter((f) => fs.statSync(f).size > 0).sort(); } catch { return []; }
}

// ---- assistant ----
const keyFile = () => path.join(app.getPath("userData"), "assistant-key.bin");
function readKey(): string | null {
  try {
    const b = fs.readFileSync(keyFile());
    return safeStorage.isEncryptionAvailable() ? safeStorage.decryptString(b) : null;
  } catch { return null; }
}
function isLocal(u: string) { try { return ["127.0.0.1", "localhost", "[::1]", "::1"].includes(new URL(u).hostname.toLowerCase()); } catch { return false; } }

export function installWorkspace() {
  ipcMain.on("ws:state", (e, s: DocState) => { states.set(e.sender.id, s); broadcast(); });
  ipcMain.handle("ws:windows", () => list());
  ipcMain.handle("ws:focus", (_e, id: number) => { const w = byId(id); if (w) { if (w.isMinimized()) w.restore(); w.focus(); } return !!w; });
  ipcMain.handle("ws:close", (_e, id: number) => { byId(id)?.close(); });
  ipcMain.handle("ws:arrange", (e, mode: string) => arrange(mode, BrowserWindow.fromWebContents(e.sender)));
  ipcMain.handle("ws:windowTabs", (e, op: string) => {
    if (op === "Merge") return mergeTabs(BrowserWindow.fromWebContents(e.sender));
    setSetting("windowTabs", op === "Tabs");
    if (op === "Windows") { tabbed.clear(); broadcast(); }
    return docWindows().length;
  });
  ipcMain.handle("ws:fullscreen", (e) => { const w = BrowserWindow.fromWebContents(e.sender); if (w) w.setFullScreen(!w.isFullScreen()); return w?.isFullScreen() ?? false; });
  // New drawings open as tabs (WINDOWTABS Tabs): a new window takes the front window's frame and joins its tab group.
  app.on("browser-window-created", (_e, w) => {
    if (readSettings().windowTabs !== true) return;
    const front = BrowserWindow.getFocusedWindow();
    if (!front || front === w) return;
    const b = front.getBounds();
    w.once("ready-to-show", () => { if (front.isMaximized()) w.maximize(); else w.setBounds(b); tabbed.add(front.webContents.id); tabbed.add(w.webContents.id); broadcast(); });
  });
  app.on("browser-window-created", (_e, w) => {
    const id = w.webContents.id;
    w.on("closed", () => { states.delete(id); tabbed.delete(id); broadcast(); });
    w.on("focus", () => broadcast());
    w.webContents.on("render-process-gone", (_ev, d) => { if (d.reason !== "clean-exit") writeReport(`Renderer process gone: ${d.reason} (exit code ${d.exitCode})`, ""); });
  });

  // Settings export / import (a JSON file; keys that belong to this computer — recent files, tokens, window frames — stay).
  const transferable = (k: string) => !/recent|token|frame\.|^archi\.b\.frame/i.test(k);
  ipcMain.handle("ws:exportSettings", async (e, local: Record<string, string>) => {
    const win = BrowserWindow.fromWebContents(e.sender)!;
    const r = await dialog.showSaveDialog(win, { title: "Export Settings", defaultPath: "Oanarina Archi Tool Settings.json", filters: [{ name: "Settings", extensions: ["json"] }] });
    if (r.canceled || !r.filePath) return null;
    const app0 = Object.fromEntries(Object.entries(readSettings()).filter(([k]) => transferable(k)));
    const ui = Object.fromEntries(Object.entries(local ?? {}).filter(([k]) => transferable(k)));
    const data = { format: "oanarina-archi-settings", version: 1, app: app0, ui };
    fs.writeFileSync(r.filePath, JSON.stringify(data, null, 1));
    return { path: r.filePath, count: Object.keys(app0).length + Object.keys(ui).length };
  });
  ipcMain.handle("ws:importSettings", async (e) => {
    const win = BrowserWindow.fromWebContents(e.sender)!;
    const r = await dialog.showOpenDialog(win, { title: "Import Settings", properties: ["openFile"], filters: [{ name: "Settings", extensions: ["json"] }] });
    if (r.canceled || !r.filePaths[0]) return null;
    let data: any;
    try { data = JSON.parse(fs.readFileSync(r.filePaths[0], "utf8")); } catch { return { error: `Cannot read ${path.basename(r.filePaths[0])}.` }; }
    if (data?.format !== "oanarina-archi-settings") return { error: `Cannot read ${path.basename(r.filePaths[0])}.` };
    let n = 0;
    for (const [k, v] of Object.entries(data.app ?? {})) if (transferable(k)) { setSetting(k, v); n++; }
    const ui = Object.fromEntries(Object.entries(data.ui ?? {}).filter(([k]) => transferable(k)));
    return { count: n + Object.keys(ui).length, ui };
  });

  // Crash reports.
  process.on("uncaughtException", (err) => { writeReport(`Exception ${err?.name ?? "Error"}: ${err?.message ?? err}`, String(err?.stack ?? "")); });
  app.on("child-process-gone", (_e, d) => { if (d.reason !== "clean-exit" && d.reason !== "killed") writeReport(`${d.type} process gone: ${d.reason} (exit code ${d.exitCode})`, d.name ?? ""); });
  ipcMain.handle("ws:crash", async (e, op: string, detail?: string) => {
    switch (op) {
      case "on": setSetting("crashReports", true); break;
      case "off": setSetting("crashReports", false); break;
      case "report": writeReport("archi-engine stopped", String(detail ?? "")); break;
      case "show": { const p = pendingReports(); if (p.length) shell.showItemInFolder(p[0]); else { fs.mkdirSync(logsFolder(), { recursive: true }); } break; }
      case "clear": { const p = pendingReports(); for (const f of p) try { fs.rmSync(f); } catch {} return { enabled: crashOn(), count: 0, removed: p.length, folder: logsFolder(), environment: environment() }; }
      case "text": return { text: pendingReports().map((f) => { try { return redact(fs.readFileSync(f, "utf8")); } catch { return ""; } }).join("\n\n") };
      case "copy": clipboard.writeText(String(detail ?? "")); break;
    }
    void e;
    return { enabled: crashOn(), count: pendingReports().length, folder: logsFolder(), environment: environment() };
  });

  // Assistant.
  ipcMain.handle("ws:assistant:hasKey", () => !!readKey());
  ipcMain.handle("ws:assistant:setKey", (_e, key: string) => {
    try {
      if (!key) { fs.rmSync(keyFile(), { force: true }); return true; }
      if (!safeStorage.isEncryptionAvailable()) return false;
      fs.mkdirSync(path.dirname(keyFile()), { recursive: true });
      fs.writeFileSync(keyFile(), safeStorage.encryptString(key), { mode: 0o600 });
      return true;
    } catch { return false; }
  });
  ipcMain.handle("ws:assistant:request", async (_e, req: { provider: string; endpoint: string; body: unknown }) => {
    const headers: Record<string, string> = { "content-type": "application/json" };
    let url: string;
    if (req.provider === "anthropic") {
      const key = readKey();
      if (!key) return { error: "Add your Anthropic API key in the assistant settings." };
      url = "https://api.anthropic.com/v1/messages";
      headers["x-api-key"] = key;
      headers["anthropic-version"] = "2023-06-01";
    } else {
      if (!isLocal(req.endpoint)) return { error: "The local model endpoint must be on this computer (localhost)." };
      url = req.endpoint;
    }
    try {
      const ctl = new AbortController();
      const t = setTimeout(() => ctl.abort(), 120000);
      const r = await fetch(url, { method: "POST", headers, body: JSON.stringify(req.body), signal: ctl.signal });
      clearTimeout(t);
      return { text: await r.text() };
    } catch (err: any) { return { error: String(err?.message ?? err) }; }
  });
}
