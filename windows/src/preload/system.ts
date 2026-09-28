// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// window.archiSystem: the VR window (VRVIEW Open) and the end of `--selftest` (src/main/system.ts).
import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("archiSystem", {
  openVR: (path: string) => ipcRenderer.invoke("system:openVR", path),
  selfTestDone: (code: number, text: string) => ipcRenderer.send("system:selftestDone", code, text),
});
