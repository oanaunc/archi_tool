// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// window.archiWS: main-process services of the workspace module (open windows for the file tabs, window arrangement
// and tabs, full screen, settings export / import, crash reports, the AI assistant's requests and key). See
// src/main/workspace.ts.
import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("archiWS", {
  setState: (s: unknown) => ipcRenderer.send("ws:state", s),
  windows: () => ipcRenderer.invoke("ws:windows"),
  onWindows: (cb: (l: unknown) => void) => { ipcRenderer.on("ws:windows", (_e, l) => cb(l)); },
  focus: (id: number) => ipcRenderer.invoke("ws:focus", id),
  close: (id: number) => ipcRenderer.invoke("ws:close", id),
  arrange: (mode: string) => ipcRenderer.invoke("ws:arrange", mode),
  windowTabs: (op: string) => ipcRenderer.invoke("ws:windowTabs", op),
  fullScreen: () => ipcRenderer.invoke("ws:fullscreen"),
  exportSettings: (local: Record<string, string>) => ipcRenderer.invoke("ws:exportSettings", local),
  importSettings: () => ipcRenderer.invoke("ws:importSettings"),
  crash: (op: string, detail?: string) => ipcRenderer.invoke("ws:crash", op, detail),
  assistantHasKey: () => ipcRenderer.invoke("ws:assistant:hasKey"),
  assistantSetKey: (key: string) => ipcRenderer.invoke("ws:assistant:setKey", key),
  assistantRequest: (req: unknown) => ipcRenderer.invoke("ws:assistant:request", req),
});
