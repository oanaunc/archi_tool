// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// window.archiDrop: the path of a file dropped on the 2D canvas (Electron 32+ has no File.path; webUtils reads it in
// the preload). Used by canvas/plan-canvas.ts for file.drop (drawings open, images / PDFs / exchange formats import).
import { contextBridge, webUtils } from "electron";

contextBridge.exposeInMainWorld("archiDrop", {
  pathForFile: (f: File) => { try { return webUtils.getPathForFile(f); } catch { return ""; } },
});
