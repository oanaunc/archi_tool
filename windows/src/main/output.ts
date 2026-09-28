// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Main-process services of the output windows (src/renderer/output): Windows printing of the plotted pages through
// Chromium's print pipeline (webContents.print with the printer, paper, copies, scale and the system dialog, like
// PrintSetupWindow.print / Plotter.printDrawing), the printer list, writing rendered images and videos, opening files
// with their default application, and copying an image to the clipboard.
import { BrowserWindow, ipcMain, shell, clipboard, nativeImage, app } from "electron";
import path from "node:path";
import fs from "node:fs";
import { withPrintOptions } from "./standards";

export interface PrintJob {
  title: string;
  /** Plotted pages: SVG documents in millimetres (the engine's plot.preview pages). */
  pages: { svg?: string; svgPath?: string; width: number; height: number }[];
  printer?: string;
  /** Printer paper: a standard name (A4, A3, Letter …), "drawing" (custom page the size of the sheet) or "roll:<mm>". */
  paper?: string;
  scaling?: "fit" | "actual" | "custom";
  percent?: number;
  copies?: number;
  showDialog?: boolean;
  landscape?: boolean;
  /** Input tray and media type (Print Schema options "feature|namespace|option", src/main/standards.ts printerCaps). */
  tray?: string;
  mediaType?: string;
}

const STANDARD: Record<string, [number, number]> = {
  A0: [841, 1189], A1: [594, 841], A2: [420, 594], A3: [297, 420], A4: [210, 297], A5: [148, 210],
  Letter: [215.9, 279.4], Legal: [215.9, 355.6], Tabloid: [279.4, 431.8], Ledger: [279.4, 431.8],
};

/** Page size in millimetres (portrait) for a job; null = the printer's default paper. */
export function pageSize(job: PrintJob): { width: number; height: number; scale: number; rotate: boolean } | null {
  const first = job.pages[0];
  if (!first) return null;
  const long = Math.max(first.width, first.height), short = Math.min(first.width, first.height);
  const paper = job.paper ?? "";
  if (paper === "drawing") return { width: short, height: long, scale: 1, rotate: first.width > first.height };
  if (paper.startsWith("roll:")) {
    // PrintOptions.page(for:mode:rollWidthMM:): the long side across the roll when it fits, else the short side, else scaled.
    const roll = Math.max(100, Number(paper.slice(5)) || 914);
    if (long <= roll + 0.2) return { width: roll, height: short, scale: 1, rotate: first.height > first.width };
    if (short <= roll + 0.2) return { width: roll, height: long, scale: 1, rotate: first.width > first.height };
    const k = roll / short;
    return { width: roll, height: long * k, scale: k, rotate: first.width > first.height };
  }
  const std = STANDARD[paper];
  if (std) return { width: std[0], height: std[1], scale: 1, rotate: false };
  return null;
}

/** The print document: one page per plotted page, true size, centred, scaled to fit or by a percentage. */
export function printHTML(job: PrintJob): string {
  const ps = pageSize(job);
  const pages = job.pages.map((p) => {
    const w = p.width, hgt = p.height;
    let fit = "";
    if (job.scaling === "custom") fit = `transform: scale(${Math.max(0.1, Math.min(10, (job.percent ?? 100) / 100))}); transform-origin: center;`;
    const text = p.svg ?? (p.svgPath ? fs.readFileSync(p.svgPath, "utf8") : "");
    const svg = text.replace(/^<svg /, `<svg class="pg" style="width:${w}mm;height:${hgt}mm;${fit}" `);
    const box = job.scaling === "fit" || !job.scaling ? "fit" : "actual";
    return `<section class="page ${box}">${svg}</section>`;
  }).join("\n");
  const size = ps ? `${ps.width}mm ${ps.height}mm` : (job.landscape ? "landscape" : "portrait");
  return `<!doctype html><html><head><meta charset="utf-8"><title>${escapeHTML(job.title)}</title><style>
@page { size: ${size}; margin: 0; }
html, body { margin: 0; padding: 0; background: #fff; }
.page { width: 100vw; height: 100vh; display: flex; align-items: center; justify-content: center; overflow: hidden; page-break-after: always; break-after: page; }
.page:last-child { page-break-after: auto; break-after: auto; }
.page.fit .pg { max-width: 100vw; max-height: 100vh; width: auto !important; height: auto !important; }
.page .pg { display: block; }
</style></head><body>${pages}</body></html>`;
}
function escapeHTML(s: string) { return s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!)); }

async function print(job: PrintJob): Promise<{ ok: boolean; error?: string }> {
  const html = printHTML(job);
  const file = path.join(app.getPath("temp"), `ArchiPrint-${process.pid}-${Date.now()}.html`);
  fs.writeFileSync(file, html, "utf8");
  const win = new BrowserWindow({ show: false, webPreferences: { sandbox: true, contextIsolation: true } });
  try {
    await win.loadFile(file);
    const ps = pageSize(job);
    const first = job.pages[0];
    const landscape = ps ? ps.rotate : (job.landscape ?? (first ? first.width > first.height : false));
    const opts: Electron.WebContentsPrintOptions = {
      silent: !job.showDialog, printBackground: true, copies: Math.max(1, Math.min(99, job.copies ?? 1)), landscape,
      margins: { marginType: "none" }, deviceName: job.printer || undefined,
    };
    if (ps) opts.pageSize = { width: Math.round((landscape ? ps.height : ps.width) * 1000), height: Math.round((landscape ? ps.width : ps.height) * 1000) };
    if (job.scaling === "custom") opts.scaleFactor = Math.max(10, Math.min(400, Math.round(job.percent ?? 100)));
    return await new Promise((resolve) => win.webContents.print(opts, (ok, reason) => resolve(ok ? { ok } : { ok, error: reason })));
  } finally {
    setTimeout(() => { if (!win.isDestroyed()) win.destroy(); fs.rm(file, { force: true }, () => {}); }, 2000);
  }
}

export function installOutput() {
  ipcMain.handle("o:print", (_e, job: PrintJob) => withPrintOptions(job.printer ?? "", [job.tray ?? "", job.mediaType ?? ""], () => print(job)));
  ipcMain.handle("o:printers", async (e) => {
    const list = await e.sender.getPrintersAsync();
    return list.map((p) => ({ name: p.name, displayName: p.displayName || p.name, isDefault: !!(p as any).isDefault, description: p.description ?? "" }));
  });
  ipcMain.handle("o:writeBytes", (_e, p: string, data: Uint8Array) => { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, Buffer.from(data)); return true; });
  ipcMain.handle("o:readBytes", (_e, p: string) => { try { return new Uint8Array(fs.readFileSync(p)); } catch { return null; } });
  ipcMain.handle("o:copyFile", (_e, from: string, to: string) => { fs.mkdirSync(path.dirname(to), { recursive: true }); fs.copyFileSync(from, to); return true; });
  ipcMain.handle("o:openPath", async (_e, p: string) => (await shell.openPath(p)) === "");
  ipcMain.handle("o:reveal", (_e, p: string) => { shell.showItemInFolder(p); return true; });
  ipcMain.handle("o:copyImage", (_e, data: Uint8Array) => { clipboard.writeImage(nativeImage.createFromBuffer(Buffer.from(data))); return true; });
  ipcMain.handle("o:folders", () => ({ pictures: app.getPath("pictures"), temp: app.getPath("temp"), documents: app.getPath("documents"), desktop: app.getPath("desktop") }));
  ipcMain.handle("o:list", (_e, dir: string) => { try { return fs.readdirSync(dir); } catch { return []; } });
  ipcMain.handle("o:exists", (_e, p: string) => fs.existsSync(p));
}
