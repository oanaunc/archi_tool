// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Exposes the engine RPC and a few native services to the renderer as window.archi.
import { contextBridge, ipcRenderer } from "electron";
import type { ArchiBridge } from "../shared/protocol";
import "./partb";
import "./output";
import "./canvas";
import "./spell";
import "./workspace";
import "./standards";
import "./system";

const bridge: ArchiBridge = {
  async rpc(method, params) {
    try { return await ipcRenderer.invoke("engine:rpc", method, params ?? {}); }
    catch (e: any) {
      const m = String(e?.message ?? e).replace(/^Error invoking remote method '[^']+': (Error: )?/, "");
      try { throw JSON.parse(m); } catch (parsed) { if (parsed && typeof parsed === "object") throw parsed; throw { code: -32603, message: m }; }
    }
  },
  onNotify(cb) { ipcRenderer.on("engine:notify", (_e, n) => cb(n)); },
  platform: process.platform,
  windowControl: (action) => ipcRenderer.invoke("window:control", action),
  onWindowState(cb) { ipcRenderer.on("window:state", (_e, s) => cb(s)); },
  openFileDialog: (opts) => ipcRenderer.invoke("dialog:open", opts),
  saveFileDialog: (opts) => ipcRenderer.invoke("dialog:save", opts),
  recentFiles: () => ipcRenderer.invoke("recent:list"),
  addRecent: (p) => ipcRenderer.invoke("recent:add", p),
  clearRecent: () => ipcRenderer.invoke("recent:clear"),
  samplePath: (name) => ipcRenderer.invoke("sample:path", name),
  newWindow: (req) => ipcRenderer.invoke("window:new", req),
  initialRequest: () => ipcRenderer.invoke("window:request"),
  openExternal: (url) => ipcRenderer.invoke("shell:openExternal", url),
  setTitle: (t) => ipcRenderer.send("window:title", t),
  nativeCaptions: process.platform === "win32",
  setTheme: (theme) => { ipcRenderer.send("window:theme", theme); void ipcRenderer.invoke("settings:set", "theme", theme); },
  fileUrl: (p) => "archi-file://" + encodeURIComponent(p),
  // Settings and dialogs (src/main/settings-ipc.ts).
  paths: () => ipcRenderer.invoke("settings:paths"),
  setSetting: (key, value) => ipcRenderer.invoke("settings:set", key, value),
  revealPath: (p) => ipcRenderer.invoke("shell:revealPath", p),
  chooseFolder: (opts) => ipcRenderer.invoke("dialog:folder", opts),
  readTextFile: (p) => ipcRenderer.invoke("fs:readText", p),
  writeTextFile: (p, text) => ipcRenderer.invoke("fs:writeText", p, text),
  removeFile: (p) => ipcRenderer.invoke("fs:remove", p),
};
contextBridge.exposeInMainWorld("archi", bridge);
