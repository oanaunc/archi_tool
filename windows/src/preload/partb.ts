// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// window.archiB: main-process services of the tool windows (script context, agent server, library files, folder
// dialog, clipboard, tutorials). See src/main/partb.ts.
import { contextBridge, ipcRenderer } from "electron";

const on = (channel: string) => (cb: (payload: any) => void) => { ipcRenderer.on(channel, (_e, p) => cb(p)); };

contextBridge.exposeInMainWorld("archiB", {
  paths: () => ipcRenderer.invoke("b:paths"),
  readText: (p: string) => ipcRenderer.invoke("b:fs:read", p),
  writeText: (p: string, text: string) => ipcRenderer.invoke("b:fs:write", p, text),
  writeBase64: (p: string, b64: string) => ipcRenderer.invoke("b:fs:writeBase64", p, b64),
  list: (dir: string, exts?: string[]) => ipcRenderer.invoke("b:fs:list", dir, exts),
  mkdir: (dir: string) => ipcRenderer.invoke("b:fs:mkdir", dir),
  remove: (p: string) => ipcRenderer.invoke("b:fs:remove", p),
  exists: (p: string) => ipcRenderer.invoke("b:fs:exists", p),
  reveal: (p: string) => ipcRenderer.invoke("b:shell:reveal", p),
  chooseFolder: (title?: string) => ipcRenderer.invoke("b:dialog:folder", title),
  copy: (text: string) => ipcRenderer.invoke("b:clipboard", text),
  tutorials: () => ipcRenderer.invoke("b:tutorials"),
  scriptEval: (code: string, name?: string) => ipcRenderer.invoke("b:script:eval", code, name),
  scriptReset: () => ipcRenderer.invoke("b:script:reset"),
  scriptCallGlobal: (name: string, arg: unknown) => ipcRenderer.invoke("b:script:callGlobal", name, arg),
  onScriptLine: on("b:script:line"),
  onScriptPanel: on("b:script:panel"),
  agentStatus: () => ipcRenderer.invoke("b:agent:status"),
  agentStart: (port?: number) => ipcRenderer.invoke("b:agent:start", port),
  agentStop: () => ipcRenderer.invoke("b:agent:stop"),
  agentPrefs: (p: unknown) => ipcRenderer.invoke("b:agent:prefs", p),
  onAgentStatus: on("b:agent:status"),
  onScreenshotRequest: on("b:agent:screenshot"),
  screenshotReply: (id: number, result: unknown) => ipcRenderer.invoke("b:agent:screenshot:reply", id, result),
});
