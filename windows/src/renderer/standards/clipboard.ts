// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Clipboard interoperability (ExternalPaste / Artwork in AppRound11Support.swift): PASTESPECIAL reads what another app
// copied (SVG or PDF vectors, pictures, DXF text, plain text, files copied in Explorer) and inserts it at the point the
// engine asked for (clipboard.paste: one undo step "Paste SVG" …; files go through file.drop like a drop on the plan);
// COPYPICTURE puts the engine's vector PDF, the SVG and a 1600 px PNG (Artwork.thumbnail: square, white, 90 % fit)
// on the clipboard for other apps.
import type { App } from "../app";
import { std, webRecord, b64 } from "./native";

/** Test page stand-in for the Windows clipboard ({type, data} or {files}). */
function testClipboard(): { files?: string[]; type?: string; data?: string } | null { return (window as any).archiTestClipboard ?? null; }

export async function clipboardHasExternal(): Promise<boolean> {
  const n = std();
  if (n) { try { return await n.clipboardHasExternal(); } catch { return true; } }
  return !!testClipboard();
}

async function readExternal(): Promise<{ files?: string[]; type?: string; data?: string } | null> {
  const n = std();
  if (n) return n.clipboardRead();
  const t = testClipboard();
  if (t) return t;
  try {
    const text = (await navigator.clipboard.readText()).trim();
    if (!text) return null;
    const type = text.startsWith("<svg") || (text.startsWith("<?xml") && text.includes("<svg")) ? "svg" : "text";
    return { type, data: b64(new TextEncoder().encode(text)) };
  } catch { return null; }
}

export async function pasteSpecial(app: App, x: number, y: number) {
  const c = await readExternal();
  if (!c || (!c.files?.length && !c.data)) { app.print("The clipboard holds nothing from another app (use PASTECLIP for drawing objects)."); return; }
  if (c.files?.length) {
    const r = await app.tryCall("file.drop", { paths: c.files, x, y });
    if (r) {
      for (const p of r.open ?? []) await app.open(p);
      for (const p of r.scripts ?? []) await app.action("@runScript:" + p);
    }
  } else {
    await app.tryCall("clipboard.paste", { type: c.type ?? "text", data: c.data, x, y });
  }
  await app.refresh(["drawing", "selection", "properties", "history", "layers"]);
}

/** A square white bitmap of the SVG picture, fitted with a 5 % margin (Artwork.thumbnail). */
export async function rasterize(svg: string, size = 1600): Promise<Uint8Array | null> {
  // data: URL (the window's Content Security Policy allows data: images, not blob:).
  const url = "data:image/svg+xml;base64," + b64(new TextEncoder().encode(svg));
  try {
    const img = new Image();
    await new Promise<void>((res, rej) => { img.onload = () => res(); img.onerror = () => rej(new Error("svg")); img.src = url; });
    const w = img.naturalWidth || 1, hgt = img.naturalHeight || 1;
    const c = document.createElement("canvas");
    c.width = c.height = size;
    const ctx = c.getContext("2d")!;
    ctx.fillStyle = "#ffffff"; ctx.fillRect(0, 0, size, size);
    const k = (size * 0.9) / Math.max(w, hgt);
    ctx.drawImage(img, (size - w * k) / 2, (size - hgt * k) / 2, w * k, hgt * k);
    const blob: Blob | null = await new Promise((res) => c.toBlob(res, "image/png"));
    return blob ? new Uint8Array(await blob.arrayBuffer()) : null;
  } catch { return null; }
}

export async function copyPicture(app: App, p: { pdf?: string; svg?: string }) {
  const png = p.svg ? await rasterize(p.svg) : null;
  if (!png) { app.print("Could not make the picture."); return; }
  const n = std();
  if (n) { await n.writePicture({ png, pdfPath: p.pdf, svg: p.svg }); return; }
  webRecord.picture = { png: png.length, pdfPath: p.pdf, svg: p.svg?.length };
  try { await navigator.clipboard.write([new ClipboardItem({ "image/png": new Blob([png as unknown as BlobPart], { type: "image/png" }) })]); } catch { /* no permission in the test page */ }
}
