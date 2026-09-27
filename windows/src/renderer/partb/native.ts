// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Access to the main-process services (window.archiB, src/preload/partb.ts). In a plain browser (tests, design review)
// files live in localStorage, scripts run in a Web Worker (cross-origin isolated pages) and the agent server is off.
import type { App } from "../app";
import { ScriptHost } from "../../shared/script-host";
import type { ScriptResult } from "../../shared/script-runtime";

export interface FileEntry { name: string; path: string; dir: boolean; mtime: number }
export interface Paths { appData: string; scripts: string; materials: string; nodePackages: string; plugins: string; agentInfo: string; documents: string; resources: string; tutorials: string; engine: string }
export interface AgentStatus { running: boolean; port: number; token: string; error: string; infoFile: string; autoStart: boolean; prefPort: number }
export interface Tutorial { name: string; file: string; title: string; summary: string; steps: number; seconds: number }

const B = (): any => (window as any).archiB ?? null;
export const isElectron = () => !!B();

// ---- browser fallback file store ----
const VFS = "archi.vfs:";
function vfsList(dir: string): FileEntry[] {
  const pre = dir.replace(/[\\/]+$/, "") + "/";
  const out = new Map<string, FileEntry>();
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i)!;
    if (!k.startsWith(VFS + pre)) continue;
    const rest = k.slice(VFS.length + pre.length);
    const name = rest.split("/")[0];
    out.set(name, { name, path: pre + name, dir: rest.includes("/"), mtime: 0 });
  }
  return [...out.values()].sort((a, b) => a.name.localeCompare(b.name));
}

let pathsCache: Paths | null = null;
export async function paths(): Promise<Paths> {
  if (pathsCache) return pathsCache;
  const b = B();
  pathsCache = b ? await b.paths() : { appData: "/Oanarina Archi Tool", scripts: "/Oanarina Archi Tool/Scripts", materials: "/Oanarina Archi Tool/Materials", nodePackages: "/Oanarina Archi Tool/NodePackages",
    plugins: "/Oanarina Archi Tool/Plugins", agentInfo: "/Oanarina Archi Tool/agent.json", documents: "/Documents", resources: "/resources", tutorials: "/resources/tutorials", engine: "archi-engine.exe" };
  return pathsCache!;
}
export const sep = () => (navigator.platform.startsWith("Win") && isElectron() ? "\\" : "/");
export function join(...parts: string[]) { const s = parts[0]?.includes("\\") ? "\\" : "/"; return parts.map((p, i) => (i === 0 ? p.replace(/[\\/]+$/, "") : p.replace(/^[\\/]+|[\\/]+$/g, ""))).join(s); }
export function basename(p: string) { return p.split(/[\\/]/).pop() ?? p; }
export function dirname(p: string) { const i = Math.max(p.lastIndexOf("/"), p.lastIndexOf("\\")); return i > 0 ? p.slice(0, i) : p; }
export function stem(p: string) { return basename(p).replace(/\.[^.]*$/, ""); }

export async function readText(p: string): Promise<string | null> { const b = B(); if (b) return b.readText(p); return localStorage.getItem(VFS + p); }
export async function writeText(p: string, text: string): Promise<void> { const b = B(); if (b) { await b.writeText(p, text); return; } localStorage.setItem(VFS + p, text); }
export async function writeBase64(p: string, b64: string): Promise<boolean> { const b = B(); if (b) { await b.writeBase64(p, b64); return true; } return false; }
export async function list(dir: string, exts?: string[]): Promise<FileEntry[]> {
  const b = B();
  if (b) return b.list(dir, exts);
  return vfsList(dir).filter((f) => f.dir || !exts || exts.includes((f.name.split(".").pop() ?? "").toLowerCase()));
}
export async function mkdir(dir: string) { const b = B(); if (b) await b.mkdir(dir); }
export async function remove(p: string) { const b = B(); if (b) await b.remove(p); else localStorage.removeItem(VFS + p); }
export async function exists(p: string): Promise<boolean> { const b = B(); if (b) return b.exists(p); return localStorage.getItem(VFS + p) !== null; }
export async function reveal(app: App, p: string) { const b = B(); if (b) await b.reveal(p); else app.print(`Folder: ${p}`); }
export async function chooseFolder(title: string): Promise<string | null> { const b = B(); if (b) return b.chooseFolder(title); const v = prompt(title, "/Documents"); return v || null; }
export async function copy(text: string) { const b = B(); if (b) { await b.copy(text); return; } try { await navigator.clipboard.writeText(text); } catch { /* not allowed */ } }
export async function tutorials(): Promise<Tutorial[]> { const b = B(); return b ? b.tutorials() : []; }
export async function openFile(app: App, title: string, filters: { name: string; extensions: string[] }[]): Promise<string | null> {
  const n = app.engine.native;
  if (n) return n.openFileDialog({ title, filters });
  const v = prompt(title + " (path)", "");
  return v || null;
}
export async function saveFile(app: App, title: string, defaultPath: string, filters: { name: string; extensions: string[] }[]): Promise<string | null> {
  const n = app.engine.native;
  if (n) return n.saveFileDialog({ title, defaultPath, filters });
  const v = prompt(title + " (path)", defaultPath);
  return v || null;
}
export function fileUrl(app: App, p: string | null | undefined): string | null {
  if (!p) return null;
  const n = app.engine.native;
  return n ? n.fileUrl(p) : null;
}

// ---- scripts ----
let browserHost: ScriptHost | null = null;
const lineListeners: ((t: string) => void)[] = [];
const panelListeners: ((spec: any) => void)[] = [];
export function onScriptLine(cb: (t: string) => void) { lineListeners.push(cb); }
export function onScriptPanel(cb: (spec: any) => void) { panelListeners.push(cb); }
let wired = false;
function wire(app: App) {
  if (wired) return;
  wired = true;
  const b = B();
  if (b) {
    b.onScriptLine((t: string) => lineListeners.forEach((f) => f(t)));
    b.onScriptPanel((s: any) => panelListeners.forEach((f) => f(s)));
  } else {
    app.engine.onNotify((n) => browserHost?.notify(n.method, n.params));
  }
}
function host(app: App): ScriptHost | null {
  if (browserHost) return browserHost;
  if (typeof SharedArrayBuffer === "undefined" || !(self as any).crossOriginIsolated) return null;
  browserHost = new ScriptHost({
    makeWorker: (sab) => {
      const w = new Worker("script-worker.js");
      void sab;
      return { post: (m) => w.postMessage(m), onMessage: (cb) => { w.onmessage = (e) => cb(e.data); }, terminate: () => w.terminate() };
    },
    engineCall: (m, p) => app.engine.call(m, p),
    onLine: (t) => lineListeners.forEach((f) => f(t)),
    onPanel: (s) => panelListeners.forEach((f) => f(s)),
  });
  return browserHost;
}
export function initScripts(app: App) { wire(app); }
export async function scriptEval(app: App, code: string, name = "console.js"): Promise<ScriptResult> {
  wire(app);
  const b = B();
  if (b) return b.scriptEval(code, name);
  const hst = host(app);
  if (!hst) { const e = "✖ The JavaScript console needs the Windows app (or a cross-origin isolated page)."; lineListeners.forEach((f) => f(e)); return { output: [e], value: null, error: e }; }
  return hst.evaluate(code, name);
}
export async function scriptReset(app: App) { const b = B(); if (b) await b.scriptReset(); else host(app)?.reset(); }
export async function scriptCallGlobal(app: App, name: string, arg: unknown) { const b = B(); if (b) await b.scriptCallGlobal(name, arg); else host(app)?.callGlobal(name, arg); }

// ---- agent server ----
const statusListeners: ((s: AgentStatus) => void)[] = [];
let lastStatus: AgentStatus = { running: false, port: 47800, token: "", error: "", infoFile: "", autoStart: false, prefPort: 47800 };
export function agentLast() { return lastStatus; }
export function onAgentStatus(cb: (s: AgentStatus) => void) { statusListeners.push(cb); }
function setStatus(s: AgentStatus) { if (!s) return; lastStatus = s; statusListeners.forEach((f) => f(s)); }
export async function agentStatus(): Promise<AgentStatus> { const b = B(); if (b) setStatus(await b.agentStatus()); return lastStatus; }
export async function agentStart(port?: number): Promise<{ ok: boolean; error?: string }> {
  const b = B();
  if (!b) return { ok: false, error: "The agent server runs in the Windows app." };
  const r = await b.agentStart(port);
  setStatus(r.status);
  return r;
}
export async function agentStop() { const b = B(); if (b) setStatus(await b.agentStop()); }
export async function agentPrefs(p: { port?: number; autoStart?: boolean }) { const b = B(); if (b) setStatus(await b.agentPrefs(p)); else setStatus({ ...lastStatus, ...(p.port ? { prefPort: p.port, port: p.port } : {}), ...(p.autoStart !== undefined ? { autoStart: p.autoStart } : {}) }); }
export function initAgent(onScreenshot: (id: number, params: any) => Promise<any>) {
  const b = B();
  if (!b) return;
  b.onAgentStatus((s: AgentStatus) => setStatus(s));
  b.onScreenshotRequest(async (m: { id: number; params: any }) => {
    let r: any;
    try { r = await onScreenshot(m.id, m.params ?? {}); } catch (e: any) { r = { error: e?.message ?? String(e) }; }
    b.screenshotReply(m.id, r);
  });
  agentStatus();
}
