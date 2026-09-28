// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Native services of the graphic standards / clipboard / sharing commands (window.archiStd, src/preload/standards.ts)
// with browser fallbacks for the test page (the async Clipboard API, a record of what was shared or opened).

export interface StdNative {
  clipboardHasExternal(): Promise<boolean>;
  clipboardRead(): Promise<{ files?: string[]; type?: string; data?: string } | null>;
  writePicture(p: { png: Uint8Array; pdfPath?: string; svg?: string }): Promise<boolean>;
  share(paths: string[]): Promise<{ ok: boolean; error?: string }>;
  copyFiles(paths: string[]): Promise<boolean>;
  openFile(p: string): Promise<boolean>;
  reveal(p: string): Promise<boolean>;
  printerCaps(printer: string): Promise<{ trays: Opt[]; media: Opt[]; papers: Opt[] }>;
}
export interface Opt { value: string; title: string }

export function std(): StdNative | null { return ((window as any).archiStd as StdNative) ?? null; }

/** What the browser build did instead of the native calls (tests read it). */
export const webRecord: { shared: string[][]; opened: string[]; picture: { png: number; pdfPath?: string; svg?: number } | null; spoken: string[] } = { shared: [], opened: [], picture: null, spoken: [] };
(window as any).archiStdRecord = webRecord;

export function b64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}
