// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// window.archiOut: main-process services of the output windows (printing, printers, image and video files). See
// src/main/output.ts.
import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("archiOut", {
  print: (job: unknown) => ipcRenderer.invoke("o:print", job),
  printers: () => ipcRenderer.invoke("o:printers"),
  writeBytes: (p: string, data: Uint8Array) => ipcRenderer.invoke("o:writeBytes", p, data),
  readBytes: (p: string) => ipcRenderer.invoke("o:readBytes", p),
  copyFile: (from: string, to: string) => ipcRenderer.invoke("o:copyFile", from, to),
  openPath: (p: string) => ipcRenderer.invoke("o:openPath", p),
  reveal: (p: string) => ipcRenderer.invoke("o:reveal", p),
  copyImage: (data: Uint8Array) => ipcRenderer.invoke("o:copyImage", data),
  folders: () => ipcRenderer.invoke("o:folders"),
  list: (dir: string) => ipcRenderer.invoke("o:list", dir),
  exists: (p: string) => ipcRenderer.invoke("o:exists", p),
});
