// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// window.archiStd: main-process services of the graphic standards, clipboard and sharing commands (src/main/standards.ts).
import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("archiStd", {
  clipboardHasExternal: () => ipcRenderer.invoke("st:clipboardHasExternal"),
  clipboardRead: () => ipcRenderer.invoke("st:clipboardRead"),
  writePicture: (p: { png: Uint8Array; pdfPath?: string; svg?: string }) => ipcRenderer.invoke("st:writePicture", p),
  share: (paths: string[]) => ipcRenderer.invoke("st:share", paths),
  copyFiles: (paths: string[]) => ipcRenderer.invoke("st:copyFiles", paths),
  openFile: (p: string) => ipcRenderer.invoke("st:openFile", p),
  reveal: (p: string) => ipcRenderer.invoke("st:reveal", p),
  printerCaps: (printer: string) => ipcRenderer.invoke("st:printerCaps", printer),
});
