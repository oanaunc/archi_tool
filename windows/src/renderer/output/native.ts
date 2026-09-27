// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Native services of the output windows (window.archiOut, src/preload/output.ts) with browser fallbacks for the test
// page: printing, printers, writing bytes, opening files, clipboard images, file dialogs.
import type { App } from "../app";

export interface OutNative {
  print(job: unknown): Promise<{ ok: boolean; error?: string }>;
  printers(): Promise<{ name: string; displayName: string; isDefault: boolean; description: string }[]>;
  writeBytes(p: string, data: Uint8Array): Promise<boolean>;
  readBytes(p: string): Promise<Uint8Array | null>;
  copyFile(from: string, to: string): Promise<boolean>;
  openPath(p: string): Promise<boolean>;
  reveal(p: string): Promise<boolean>;
  copyImage(data: Uint8Array): Promise<boolean>;
  folders(): Promise<{ pictures: string; temp: string; documents: string; desktop: string }>;
  list(dir: string): Promise<string[]>;
  exists(p: string): Promise<boolean>;
}

export function out(): OutNative | null { return ((window as any).archiOut as OutNative) ?? null; }

/** Files "written" in the browser test page (path → bytes), so tests can inspect them. */
export const webFiles = new Map<string, Uint8Array>();
(window as any).archiOutputFiles = webFiles;

export async function writeBytes(path: string, data: Uint8Array): Promise<boolean> {
  const n = out();
  if (n) return n.writeBytes(path, data);
  webFiles.set(path, data);
  return true;
}

/** Save dialog (native) or the suggested name (browser). */
export async function saveDialog(app: App, title: string, suggested: string, filters: { name: string; extensions: string[] }[]): Promise<string | null> {
  const n = app.engine.native;
  if (!n) return suggested;
  const dir = app.info?.path ? app.info.path.replace(/[\\/][^\\/]*$/, "") : null;
  return n.saveFileDialog({ title, defaultPath: dir ? `${dir}\\${suggested}` : suggested, filters });
}

export async function blobBytes(b: Blob): Promise<Uint8Array> { return new Uint8Array(await b.arrayBuffer()); }

/** RGBA pixels (top row first) → PNG or JPEG bytes. */
export async function encodePixels(px: { width: number; height: number; data: Uint8Array | Uint8ClampedArray }, type: "image/png" | "image/jpeg" = "image/png", quality = 0.92): Promise<Uint8Array> {
  const cv = document.createElement("canvas");
  cv.width = px.width; cv.height = px.height;
  cv.getContext("2d")!.putImageData(new ImageData(new Uint8ClampedArray(px.data) as any, px.width, px.height), 0, 0);
  const blob = await new Promise<Blob>((res, rej) => cv.toBlob((b) => (b ? res(b) : rej(new Error("Image encoding failed."))), type, quality));
  return blobBytes(blob);
}

export function dataURL(px: { width: number; height: number; data: Uint8Array | Uint8ClampedArray }): string {
  const cv = document.createElement("canvas");
  cv.width = px.width; cv.height = px.height;
  cv.getContext("2d")!.putImageData(new ImageData(new Uint8ClampedArray(px.data) as any, px.width, px.height), 0, 0);
  return cv.toDataURL("image/png");
}

export function base64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

export function fileName(p: string): string { return p.split(/[\\/]/).pop() ?? p; }
export function docName(app: App): string { return app.info?.title ?? "Untitled"; }
export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
