// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Main-process services of the graphic standards / clipboard / sharing commands (src/renderer/standards):
//  - the Windows clipboard read the way the Mac ExternalPaste reads the pasteboard (SVG, PDF, PNG, JPEG, Explorer files,
//    text) and the pictures COPYPICTURE puts there (PNG + bitmap, "Portable Document Format", "image/svg+xml") in one
//    clipboard object, which Electron's clipboard API cannot do (PowerShell / .NET DataObject);
//  - the Windows share sheet for files (the Explorer "Share" verb, Windows.ModernShare), copying files to the clipboard
//    and opening a file with its default app (the 3D viewer for the AR export);
//  - the input trays and media types of a printer (Print Schema capabilities of the print queue) and printing with a
//    chosen tray / media (the user print ticket of the queue is set for the job and restored afterwards), which
//    Chromium's print settings do not expose. PrintSetupWindow / PPDOptions on the Mac.
import { ipcMain, clipboard, nativeImage, shell, app } from "electron";
import { execFile } from "node:child_process";
import path from "node:path";
import fs from "node:fs";

const isWin = process.platform === "win32";

/** Runs a PowerShell script (STA, no profile); variables are passed in the environment (ARCHI_*), never spliced. */
export function powershell(script: string, env: Record<string, string> = {}, timeout = 20000): Promise<{ ok: boolean; out: string; err: string }> {
  return new Promise((resolve) => {
    if (!isWin) { resolve({ ok: false, out: "", err: "Windows only" }); return; }
    execFile("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-STA", "-Command", script],
      { env: { ...process.env, ...env }, windowsHide: true, timeout, maxBuffer: 16 << 20 },
      (e, out, err) => resolve({ ok: !e, out: String(out ?? ""), err: String(err ?? e?.message ?? "") }));
  });
}

// ---- clipboard ----

/** Clipboard formats that make Paste from Other App possible (ExternalPaste.hasContent). */
export function clipboardHasExternal(): boolean {
  const f = clipboard.availableFormats();
  if (f.includes(ARCHI_FORMAT)) return false;
  if (explorerFiles().length) return true;
  if (f.some((x) => /svg|pdf|portable document|image\/|png|jfif|jpeg|dxf/i.test(x))) return true;
  return clipboard.readText().trim().length > 0;
}
/** Marker of clipboard content written by Archi Tool itself (drawing objects are pasted with PASTECLIP). */
export const ARCHI_FORMAT = "application/x-oanarina-archi";

function explorerFiles(): string[] {
  if (!isWin) return [];
  try {
    const b = clipboard.readBuffer("FileNameW");
    if (!b.length) return [];
    const s = b.toString("utf16le").replace(/\0+$/, "");
    return s ? [s] : [];
  } catch { return []; }
}

function buf(fmt: string): Buffer | null {
  try { const b = clipboard.readBuffer(fmt); return b.length ? b : null; } catch { return null; }
}

/** Content from another app, most specific first (ExternalPaste.content): files, SVG, DXF, PDF, PNG, JPEG, other bitmaps, text. */
export function readExternal(): { files?: string[]; type?: string; data?: string } | null {
  const formats = clipboard.availableFormats();
  if (formats.includes(ARCHI_FORMAT)) return null;
  const files = explorerFiles();
  if (files.length) return { files };
  const pick = (names: string[]) => { for (const n of names) { const b = formats.includes(n) || isWin ? buf(n) : null; if (b) return b; } return null; };
  const svg = pick(["image/svg+xml"]);
  if (svg) return { type: "svg", data: svg.toString("base64") };
  const dxf = pick(["com.autodesk.dxf", "application/dxf"]);
  if (dxf) return { type: "dxf", data: dxf.toString("base64") };
  const pdf = pick(["Portable Document Format", "application/pdf"]);
  if (pdf && pdf.subarray(0, 4).toString() === "%PDF") return { type: "pdf", data: pdf.toString("base64") };
  const png = pick(["PNG", "image/png"]);
  if (png) return { type: "png", data: png.toString("base64") };
  const jpg = pick(["JFIF", "image/jpeg"]);
  if (jpg) return { type: "jpeg", data: jpg.toString("base64") };
  const img = clipboard.readImage();
  if (!img.isEmpty()) return { type: "png", data: img.toPNG().toString("base64") };
  const t = clipboard.readText().trim();
  if (!t) return null;
  if (t.startsWith("<svg") || (t.startsWith("<?xml") && t.includes("<svg"))) return { type: "svg", data: Buffer.from(t, "utf8").toString("base64") };
  return { type: "text", data: Buffer.from(t, "utf8").toString("base64") };
}

/** COPYPICTURE: PNG (and a bitmap), the vector PDF and the SVG in one clipboard object. */
export async function writePicture(p: { png: Uint8Array; pdfPath?: string; svg?: string }): Promise<boolean> {
  const png = Buffer.from(p.png);
  if (isWin) {
    const dir = fs.mkdtempSync(path.join(app.getPath("temp"), "ArchiPicture-"));
    const pngPath = path.join(dir, "picture.png");
    fs.writeFileSync(pngPath, png);
    let svgPath = "";
    if (p.svg) { svgPath = path.join(dir, "picture.svg"); fs.writeFileSync(svgPath, p.svg, "utf8"); }
    const script = `
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$o = New-Object System.Windows.Forms.DataObject
$png = [IO.File]::ReadAllBytes($env:ARCHI_PNG)
$o.SetData('PNG', (New-Object IO.MemoryStream(,$png)))
$o.SetImage([Drawing.Image]::FromStream((New-Object IO.MemoryStream(,$png))))
if ($env:ARCHI_PDF -and (Test-Path -LiteralPath $env:ARCHI_PDF)) { $o.SetData('Portable Document Format', (New-Object IO.MemoryStream(,[IO.File]::ReadAllBytes($env:ARCHI_PDF)))) }
if ($env:ARCHI_SVG) { $o.SetData('image/svg+xml', (New-Object IO.MemoryStream(,[IO.File]::ReadAllBytes($env:ARCHI_SVG)))) }
[Windows.Forms.Clipboard]::SetDataObject($o, $true)`;
    const r = await powershell(script, { ARCHI_PNG: pngPath, ARCHI_PDF: p.pdfPath ?? "", ARCHI_SVG: svgPath });
    setTimeout(() => fs.rm(dir, { recursive: true, force: true }, () => {}), 5000);
    if (r.ok) return true;
  }
  clipboard.writeImage(nativeImage.createFromBuffer(png));
  return true;
}

// ---- sharing ----

/** The Windows share sheet for files of one folder (Explorer's Share, verb Windows.ModernShare). */
export async function shareFiles(paths: string[]): Promise<{ ok: boolean; error?: string }> {
  if (!paths.length) return { ok: false, error: "nothing to share" };
  if (!isWin) return { ok: false, error: "The Windows share sheet needs Windows 10 or later." };
  const dir = path.dirname(paths[0]);
  const names = paths.filter((p) => path.dirname(p) === dir).map((p) => path.basename(p)).join(";");
  const script = `
$sh = New-Object -ComObject Shell.Application
$f = $sh.Namespace($env:ARCHI_DIR)
$items = $f.Items()
$items.Filter(0x40, $env:ARCHI_NAMES)
if ($items.Count -lt 1) { exit 2 }
$items.InvokeVerbEx('Windows.ModernShare')
Start-Sleep -Milliseconds 400`;
  const r = await powershell(script, { ARCHI_DIR: dir, ARCHI_NAMES: names });
  return r.ok ? { ok: true } : { ok: false, error: r.err.trim() || "The share sheet could not be opened." };
}

/** Copies files to the clipboard (paste them into Mail, Teams, Explorer …). */
export async function copyFiles(paths: string[]): Promise<boolean> {
  if (!isWin || !paths.length) return false;
  const r = await powershell("Set-Clipboard -LiteralPath ($env:ARCHI_PATHS -split '\\|')", { ARCHI_PATHS: paths.join("|") });
  return r.ok;
}

// ---- printer trays and media (Print Schema) ----

export interface PrinterCaps { trays: { value: string; title: string }[]; media: { value: string; title: string }[]; papers: { value: string; title: string }[] }

const QUEUE = `
Add-Type -AssemblyName ReachFramework, System.Printing
$name = $env:ARCHI_PRINTER
if (-not $name) { $name = (New-Object System.Printing.LocalPrintServer).DefaultPrintQueue.FullName }
if ($name.StartsWith('\\\\')) { $i = $name.IndexOf('\\', 2); $q = New-Object System.Printing.PrintQueue((New-Object System.Printing.PrintServer($name.Substring(0, $i))), $name.Substring($i + 1)) }
else { $q = (New-Object System.Printing.LocalPrintServer).GetPrintQueue($name) }
`;

/** Options of a printer's input bins, media types and paper sizes (value = feature|namespace|option). */
export async function printerCaps(printer: string): Promise<PrinterCaps> {
  const script = QUEUE + `
$xml = New-Object Xml.XmlDocument
$xml.Load($q.GetPrintCapabilitiesAsXml())
$ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace('psf', 'http://schemas.microsoft.com/windows/2003/08/printing/printschemaframework')
function Opts($features) {
  foreach ($feat in $features) {
    $node = $xml.SelectSingleNode("//psf:Feature[substring-after(@name, ':') = '$feat']", $ns)
    if (-not $node) { continue }
    foreach ($o in $node.SelectNodes('psf:Option', $ns)) {
      $n = $o.GetAttribute('name'); $local = $n.Substring($n.IndexOf(':') + 1); $prefix = $n.Substring(0, [Math]::Max(0, $n.IndexOf(':')))
      $uri = if ($prefix) { $o.GetNamespaceOfPrefix($prefix) } else { '' }
      $d = $o.SelectSingleNode("psf:Property[substring-after(@name, ':') = 'DisplayName']/psf:Value", $ns)
      [pscustomobject]@{ value = "$feat|$uri|$local"; title = $(if ($d) { $d.InnerText } else { $local }) }
    }
    return
  }
}
[pscustomobject]@{ trays = @(Opts @('JobInputBin', 'DocumentInputBin', 'PageInputBin')); media = @(Opts @('PageMediaType')); papers = @(Opts @('PageMediaSize')) } | ConvertTo-Json -Depth 4 -Compress`;
  const r = await powershell(script, { ARCHI_PRINTER: printer });
  const empty: PrinterCaps = { trays: [], media: [], papers: [] };
  if (!r.ok) return empty;
  try {
    const j = JSON.parse(r.out.trim());
    const arr = (x: any) => (Array.isArray(x) ? x : x ? [x] : []).filter((o: any) => o?.value);
    return { trays: arr(j.trays), media: arr(j.media), papers: arr(j.papers) };
  } catch { return empty; }
}

const PSF = "http://schemas.microsoft.com/windows/2003/08/printing/printschemaframework";
const PSK = "http://schemas.microsoft.com/windows/2003/08/printing/printschemakeywords";

/** Delta print ticket selecting the given options ("feature|namespace|option"). */
export function deltaTicket(options: string[]): string {
  const feats = options.filter(Boolean).map((v, i) => {
    const [feature, uri, option] = v.split("|");
    const nsDecl = uri && uri !== PSK ? ` xmlns:o${i}="${escapeXML(uri)}"` : "";
    const optName = uri && uri !== PSK ? `o${i}:${option}` : `psk:${option}`;
    return `<psf:Feature name="psk:${feature}"${nsDecl}><psf:Option name="${escapeXML(optName)}"/></psf:Feature>`;
  }).join("");
  return `<?xml version="1.0" encoding="UTF-8"?><psf:PrintTicket xmlns:psf="${PSF}" xmlns:psk="${PSK}" version="1">${feats}</psf:PrintTicket>`;
}
function escapeXML(s: string) { return s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!)); }

/**
 * Runs `job` with the queue's user print ticket set to the chosen tray / media (Chromium prints with the queue's
 * user defaults for settings it does not control) and restores the previous ticket afterwards.
 */
export async function withPrintOptions<T>(printer: string, options: string[], job: () => Promise<T>): Promise<T> {
  const chosen = options.filter(Boolean);
  if (!isWin || !chosen.length) return job();
  const dir = fs.mkdtempSync(path.join(app.getPath("temp"), "ArchiTicket-"));
  const delta = path.join(dir, "delta.xml"), backup = path.join(dir, "backup.xml");
  fs.writeFileSync(delta, deltaTicket(chosen), "utf8");
  const set = QUEUE + `
$fs = [IO.File]::Create($env:ARCHI_BACKUP); $q.UserPrintTicket.SaveTo($fs); $fs.Close()
$ds = [IO.File]::OpenRead($env:ARCHI_DELTA); $d = New-Object System.Printing.PrintTicket($ds); $ds.Close()
$r = $q.MergeAndValidatePrintTicket($q.UserPrintTicket, $d)
$q.UserPrintTicket = $r.ValidatedPrintTicket
$q.Commit()`;
  const applied = await powershell(set, { ARCHI_PRINTER: printer, ARCHI_DELTA: delta, ARCHI_BACKUP: backup });
  try { return await job(); }
  finally {
    if (applied.ok) {
      const restore = QUEUE + `
$bs = [IO.File]::OpenRead($env:ARCHI_BACKUP); $q.UserPrintTicket = New-Object System.Printing.PrintTicket($bs); $bs.Close()
$q.Commit()`;
      // After the spooler has taken the job.
      setTimeout(() => { void powershell(restore, { ARCHI_PRINTER: printer, ARCHI_BACKUP: backup }).then(() => fs.rm(dir, { recursive: true, force: true }, () => {})); }, 4000);
    } else fs.rm(dir, { recursive: true, force: true }, () => {});
  }
}

export function installStandards() {
  ipcMain.handle("st:clipboardHasExternal", () => clipboardHasExternal());
  ipcMain.handle("st:clipboardRead", () => readExternal());
  ipcMain.handle("st:writePicture", (_e, p: { png: Uint8Array; pdfPath?: string; svg?: string }) => writePicture(p));
  ipcMain.handle("st:share", (_e, paths: string[]) => shareFiles(paths));
  ipcMain.handle("st:copyFiles", (_e, paths: string[]) => copyFiles(paths));
  ipcMain.handle("st:openFile", async (_e, p: string) => (await shell.openPath(p)) === "");
  ipcMain.handle("st:reveal", (_e, p: string) => { shell.showItemInFolder(p); return true; });
  ipcMain.handle("st:printerCaps", (_e, printer: string) => printerCaps(printer));
}
