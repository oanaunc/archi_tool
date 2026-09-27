// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Main-process services for the tool windows: the per-window JavaScript context of the script console, plugins and
// agents (a Node worker thread with the archi API, ScriptEngine.swift on the Mac), the local agent server (JSON-RPC 2.0
// over HTTP on 127.0.0.1 with a bearer token, AgentServer.swift), file access for the libraries (scripts, snippets,
// node packages, procedural material textures), folder dialogs, the clipboard and the bundled tutorial list.
import { app, BrowserWindow, ipcMain, dialog, shell, clipboard, type WebContents } from "electron";
import path from "node:path";
import fs from "node:fs";
import http from "node:http";
import crypto from "node:crypto";
import { Worker } from "node:worker_threads";
import { ScriptHost } from "../shared/script-host";
import type { EngineProcess } from "./rpc";

interface Attached { win: BrowserWindow; engine: () => EngineProcess | null; scripts: ScriptHost }
const attached = new Map<number, Attached>();
let resourcesDir = "";
let lastFocused: number | null = null;

function appFolder() { return app.getPath("userData"); }
export function partbPaths() {
  const base = appFolder();
  return {
    appData: base,
    scripts: path.join(base, "Scripts"),
    materials: path.join(base, "Materials"),
    nodePackages: path.join(base, "NodePackages"),
    plugins: path.join(base, "Plugins"),
    agentInfo: path.join(base, "agent.json"),
    documents: app.getPath("documents"),
    resources: resourcesDir,
    tutorials: tutorialsDir(),
    engine: path.join(resourcesDir, "engine", process.platform === "win32" ? "archi-engine.exe" : "archi-engine"),
  };
}
function tutorialsDir() {
  for (const d of [path.join(resourcesDir, "tutorials"), path.resolve(resourcesDir, "../../tutorials"), path.resolve(__dirname, "../../../tutorials")]) if (fs.existsSync(d)) return d;
  return path.join(resourcesDir, "tutorials");
}

function send(wc: WebContents, channel: string, payload: unknown) { if (!wc.isDestroyed()) wc.send(channel, payload); }

/** Called for each document window when it is created (main.ts). */
export function attachPartB(win: BrowserWindow, engine: () => EngineProcess | null) {
  const id = win.webContents.id;
  const wc = win.webContents;
  const scripts = new ScriptHost({
    makeWorker: (sab) => {
      const w = new Worker(path.join(__dirname, "script-worker.js"), { workerData: { sab } });
      return { post: (m) => w.postMessage(m), onMessage: (cb) => w.on("message", cb), terminate: () => { w.terminate(); } };
    },
    engineCall: (method, params) => { const e = engine(); return e ? e.call(method, params) : Promise.reject({ code: -32000, message: "The engine is not running." }); },
    onLine: (text) => send(wc, "b:script:line", text),
    onPanel: (spec) => send(wc, "b:script:panel", spec),
  });
  const entry: Attached = { win, engine, scripts };
  attached.set(id, entry);
  const e = engine();
  e?.on("notification", (n: any) => { scripts.notify(n.method, n.params); });
  win.on("focus", () => { lastFocused = id; });
  win.on("closed", () => { scripts.dispose(); attached.delete(id); if (lastFocused === id) lastFocused = null; });
  if (lastFocused === null) lastFocused = id;
}

function entryOf(e: Electron.IpcMainInvokeEvent) { return attached.get(e.sender.id); }

// ---- agent server (AgentServer.swift) ----

interface AgentPrefs { port: number; autoStart: boolean }
const prefsFile = () => path.join(appFolder(), "agent-prefs.json");
function readPrefs(): AgentPrefs { try { return { port: 47800, autoStart: false, ...JSON.parse(fs.readFileSync(prefsFile(), "utf8")) }; } catch { return { port: 47800, autoStart: false }; } }
function writePrefs(p: AgentPrefs) { try { fs.mkdirSync(appFolder(), { recursive: true }); fs.writeFileSync(prefsFile(), JSON.stringify(p, null, 2)); } catch {} }

const agent = {
  server: null as http.Server | null,
  running: false,
  port: 47800,
  token: crypto.randomBytes(32).toString("hex"),
  lastError: "" as string,
  maxBytes: 32 << 20,
};

function agentStatus() {
  const p = readPrefs();
  return { running: agent.running, port: agent.running ? agent.port : p.port, token: agent.token, error: agent.lastError, infoFile: partbPaths().agentInfo, autoStart: p.autoStart, prefPort: p.port };
}
function broadcastStatus() { for (const a of attached.values()) send(a.win.webContents, "b:agent:status", agentStatus()); }

function writeInfoFile() {
  const info = { port: agent.port, token: agent.token, url: `http://127.0.0.1:${agent.port}/rpc`, pid: process.pid, started: new Date().toISOString() };
  try {
    fs.mkdirSync(appFolder(), { recursive: true });
    fs.writeFileSync(partbPaths().agentInfo, JSON.stringify(info, null, 2), { mode: 0o600 });
  } catch (e: any) { agent.lastError = `Could not write ${partbPaths().agentInfo}: ${e?.message ?? e}`; }
}

function rpcError(id: unknown, code: number, message: string) { return { jsonrpc: "2.0", id: id ?? null, error: { code, message } }; }

function targetWindow(): Attached | null {
  if (lastFocused !== null && attached.has(lastFocused)) return attached.get(lastFocused)!;
  return attached.values().next().value ?? null;
}

let shotSeq = 0;
const shotWaiters = new Map<number, (r: any) => void>();

async function agentCall(method: string, params: any): Promise<any> {
  const t = targetWindow();
  if (!t) throw { code: -32001, message: "no document is open" };
  if (method === "eval_js") {
    if (typeof params?.code !== "string") throw { code: -32602, message: "missing or invalid parameter 'code'" };
    const r = await t.scripts.evaluate(params.code, "agent.js");
    for (const l of r.output) send(t.win.webContents, "b:script:line", l);
    return { output: r.output, value: r.value, error: r.error };
  }
  if (method === "screenshot") {
    const id = ++shotSeq;
    const r = await new Promise<any>((resolve) => {
      shotWaiters.set(id, resolve);
      send(t.win.webContents, "b:agent:screenshot", { id, params });
      setTimeout(() => { if (shotWaiters.delete(id)) resolve({ error: "the window did not answer" }); }, 20000);
    });
    if (r?.error) throw { code: -32000, message: String(r.error) };
    return r;
  }
  const e = t.engine();
  if (!e) throw { code: -32000, message: "The engine is not running." };
  return e.call("agent.call", { method, params: params ?? {} });
}

async function rpc(item: any): Promise<any | null> {
  if (!item || typeof item !== "object" || Array.isArray(item) || item.jsonrpc !== "2.0" || typeof item.method !== "string") return rpcError(item?.id, -32600, "Invalid Request");
  const id = item.id;
  try {
    const result = await agentCall(item.method, item.params && typeof item.params === "object" ? item.params : {});
    return id === undefined ? null : { jsonrpc: "2.0", id, result: result === undefined ? null : result };
  } catch (e: any) {
    if (id === undefined) return null;
    const code = typeof e?.code === "number" ? (e.code === -32000 || e.code === -32601 || e.code === -32602 || e.code === -32001 ? e.code : -32000) : -32000;
    return rpcError(id, code, String(e?.message ?? e));
  }
}

function constantTimeEqual(a: string, b: string) {
  const x = Buffer.from(a), y = Buffer.from(b);
  if (x.length !== y.length) return false;
  return crypto.timingSafeEqual(x, y);
}

function reply(res: http.ServerResponse, status: number, body: unknown) {
  const data = body === null || body === undefined ? Buffer.alloc(0) : Buffer.from(JSON.stringify(body));
  const headers: Record<string, string | number> = { Server: "OanarinaArchiTool", Connection: "close", "Cache-Control": "no-store", "Content-Length": data.length };
  if (data.length) headers["Content-Type"] = "application/json; charset=utf-8";
  if (status === 401) headers["WWW-Authenticate"] = "Bearer";
  res.writeHead(status, headers);
  res.end(data);
}

function handle(req: http.IncomingMessage, res: http.ServerResponse) {
  const remote = req.socket.remoteAddress ?? "";
  if (!(remote === "127.0.0.1" || remote === "::1" || remote.startsWith("127.") || remote === "::ffff:127.0.0.1")) { req.socket.destroy(); return; }
  // DNS-rebinding protection: only loopback host names.
  const host = String(req.headers.host ?? "");
  if (host) {
    const name = host.startsWith("[") ? host.slice(1, host.indexOf("]")) : host.split(":")[0];
    if (!["127.0.0.1", "localhost", "::1"].includes(name.toLowerCase())) return reply(res, 403, { error: "forbidden host" });
  }
  const url = (req.url ?? "/").split("?")[0];
  if (req.method === "GET" && (url === "/health" || url === "/")) return reply(res, 200, { status: "ok", app: "Oanarina Archi Tool", rpc: "/rpc" });
  if (url !== "/rpc") return reply(res, url === "/health" ? 405 : 404, { error: url === "/health" ? "method not allowed" : "not found" });
  if (req.method !== "POST") return reply(res, 405, { error: "method not allowed" });
  if (!constantTimeEqual(String(req.headers.authorization ?? ""), `Bearer ${agent.token}`)) return reply(res, 401, { error: "missing or invalid bearer token" });
  if (String(req.headers["transfer-encoding"] ?? "").toLowerCase().includes("chunked")) return reply(res, 400, { error: "chunked bodies are not supported" });
  const chunks: Buffer[] = [];
  let size = 0;
  req.on("data", (c: Buffer) => { size += c.length; if (size > agent.maxBytes) { reply(res, 413, { error: "payload too large" }); req.destroy(); } else chunks.push(c); });
  req.on("end", async () => {
    if (res.writableEnded) return;
    let obj: any;
    try { obj = JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { return reply(res, 200, rpcError(null, -32700, "Parse error")); }
    let out: any;
    if (Array.isArray(obj)) {
      if (!obj.length) out = rpcError(null, -32600, "Invalid Request");
      else { const all: any[] = []; for (const it of obj) { const r = await rpc(it); if (r) all.push(r); } out = all.length ? all : null; }
    } else out = await rpc(obj);
    if (out === null) reply(res, 204, null); else reply(res, 200, out);
  });
}

function startAgent(port: number): { ok: boolean; error?: string } {
  stopAgent();
  if (!(port >= 1024 && port <= 65535)) return { ok: false, error: `invalid port ${port}` };
  const server = http.createServer(handle);
  server.on("error", (e: any) => {
    agent.lastError = `Agent server failed: ${e?.message ?? e}`;
    agent.running = false;
    try { fs.rmSync(partbPaths().agentInfo, { force: true }); } catch {}
    broadcastStatus();
  });
  server.listen(port, "127.0.0.1", () => {
    agent.running = true; agent.port = port; agent.lastError = "";
    writeInfoFile();
    broadcastStatus();
  });
  agent.server = server;
  agent.port = port;
  return { ok: true };
}
function stopAgent() {
  if (agent.server) { try { agent.server.close(); } catch {} }
  if (agent.running) { try { fs.rmSync(partbPaths().agentInfo, { force: true }); } catch {} }
  agent.server = null;
  agent.running = false;
}

// ---- files ----

function listDir(dir: string, exts?: string[]) {
  try {
    return fs.readdirSync(dir, { withFileTypes: true })
      .filter((d) => !d.name.startsWith("."))
      .filter((d) => d.isDirectory() || !exts || exts.includes(path.extname(d.name).slice(1).toLowerCase()))
      .map((d) => { const p = path.join(dir, d.name); let mtime = 0; try { mtime = fs.statSync(p).mtimeMs; } catch {} return { name: d.name, path: p, dir: d.isDirectory(), mtime }; })
      .sort((a, b) => a.name.localeCompare(b.name));
  } catch { return []; }
}

function tutorials() {
  const dir = tutorialsDir();
  return listDir(dir, ["tut"]).filter((f) => !f.dir).map((f) => {
    const text = fs.readFileSync(f.path, "utf8");
    const head = text.split(/^---\s*$/m)[0];
    const title = /^title:\s*(.+)$/m.exec(head)?.[1]?.trim() ?? f.name;
    const summary = /^summary:\s*(.+)$/m.exec(head)?.[1]?.trim() ?? "";
    const body = text.split(/^---\s*$/m).slice(1).join("\n");
    const steps = body.split(/\r?\n/).filter((l) => l.trim() && !l.trim().startsWith("#")).length;
    let seconds = 0;
    for (const m of body.matchAll(/^\s*wait\s+([\d.]+)/gm)) seconds += Number(m[1]);
    for (const m of body.matchAll(/\bfor\s+([\d.]+)\s*$/gm)) seconds += Number(m[1]) * 0.2;
    return { name: f.name.replace(/\.tut$/, ""), file: f.path, title, summary, steps, seconds: Math.round(seconds) };
  });
}

export function installPartB(opts: { resources: string }) {
  resourcesDir = opts.resources;
  ipcMain.handle("b:paths", () => partbPaths());
  ipcMain.handle("b:fs:read", (_e, p: string) => { try { return fs.readFileSync(p, "utf8"); } catch { return null; } });
  ipcMain.handle("b:fs:write", (_e, p: string, text: string) => { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, text, "utf8"); return true; });
  ipcMain.handle("b:fs:writeBase64", (_e, p: string, b64: string) => { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, Buffer.from(b64, "base64")); return true; });
  ipcMain.handle("b:fs:list", (_e, dir: string, exts?: string[]) => listDir(dir, exts));
  ipcMain.handle("b:fs:mkdir", (_e, dir: string) => { fs.mkdirSync(dir, { recursive: true }); return true; });
  ipcMain.handle("b:fs:remove", (_e, p: string) => { fs.rmSync(p, { force: true }); return true; });
  ipcMain.handle("b:fs:exists", (_e, p: string) => fs.existsSync(p));
  ipcMain.handle("b:shell:reveal", (_e, p: string) => { if (fs.existsSync(p) && fs.statSync(p).isDirectory()) shell.openPath(p); else shell.showItemInFolder(p); return true; });
  ipcMain.handle("b:dialog:folder", async (e, title?: string) => {
    const win = BrowserWindow.fromWebContents(e.sender)!;
    const r = await dialog.showOpenDialog(win, { title, properties: ["openDirectory", "createDirectory"] });
    return r.canceled ? null : r.filePaths[0];
  });
  ipcMain.handle("b:clipboard", (_e, text: string) => { clipboard.writeText(String(text)); return true; });
  ipcMain.handle("b:tutorials", () => tutorials());
  ipcMain.handle("b:script:eval", async (e, code: string, name?: string) => {
    const a = entryOf(e);
    if (!a) return { output: [], value: null, error: "No document window." };
    return a.scripts.evaluate(String(code), name || "console.js");
  });
  ipcMain.handle("b:script:reset", (e) => { entryOf(e)?.scripts.reset(); return true; });
  ipcMain.handle("b:script:callGlobal", (e, name: string, arg: unknown) => { entryOf(e)?.scripts.callGlobal(name, arg); return true; });
  ipcMain.handle("b:agent:status", () => agentStatus());
  ipcMain.handle("b:agent:start", (_e, port?: number) => {
    const p = readPrefs();
    const want = Math.max(1024, Math.min(Number(port ?? p.port) || 47800, 65535));
    const r = startAgent(want);
    return { ...r, status: agentStatus() };
  });
  ipcMain.handle("b:agent:stop", () => { stopAgent(); broadcastStatus(); return agentStatus(); });
  ipcMain.handle("b:agent:prefs", (_e, p: Partial<AgentPrefs>) => { const cur = readPrefs(); writePrefs({ ...cur, ...p }); broadcastStatus(); return agentStatus(); });
  ipcMain.handle("b:agent:screenshot:reply", (_e, id: number, result: any) => { const w = shotWaiters.get(id); shotWaiters.delete(id); w?.(result); return true; });
  app.on("will-quit", () => stopAgent());
  if (readPrefs().autoStart) app.whenReady().then(() => setTimeout(() => startAgent(readPrefs().port), 500));
}
