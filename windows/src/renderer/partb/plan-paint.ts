// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Paints an engine draw list fitted into a canvas: block library thumbnails, the node editor's plan preview, the family
// editor's plan symbols and the agent `screenshot` (the same DrawItem painter as the plan canvas).
import { decodeDrawList, paintItems, applyView, defaultParams, type Entry } from "../canvas/drawitems";

export { decodeDrawList };

export interface FitOptions { background?: string | null; margin?: number; highlight?: Set<string>; color?: string; bounds?: [number, number, number, number] | null; dpr?: number; lineweights?: boolean }

export function entriesBounds(entries: Entry[]): [number, number, number, number] | null {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const e of entries) { if (!isFinite(e.bounds[0])) continue; x0 = Math.min(x0, e.bounds[0]); y0 = Math.min(y0, e.bounds[1]); x1 = Math.max(x1, e.bounds[2]); y1 = Math.max(y1, e.bounds[3]); }
  return isFinite(x0) ? [x0, y0, x1, y1] : null;
}

/** Paints `list` (a view.drawList-shaped result or decoded entries) into the canvas, fitted with a margin. */
export function paintFitted(cv: HTMLCanvasElement, list: any, w: number, hh: number, o: FitOptions = {}): boolean {
  const entries: Entry[] = Array.isArray(list) ? list : decodeDrawList(list ?? { items: [] });
  const dpr = o.dpr ?? (devicePixelRatio || 1);
  cv.width = Math.round(w * dpr); cv.height = Math.round(hh * dpr);
  cv.style.width = w + "px"; cv.style.height = hh + "px";
  const ctx = cv.getContext("2d")!;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  if (o.background) { ctx.fillStyle = o.background; ctx.fillRect(0, 0, cv.width, cv.height); } else ctx.clearRect(0, 0, cv.width, cv.height);
  const b = o.bounds ?? entriesBounds(entries);
  if (!b || !entries.length) return false;
  const m = o.margin ?? 0.08;
  const bw = Math.max(b[2] - b[0], 1e-9), bh = Math.max(b[3] - b[1], 1e-9);
  const scale = Math.min(w / bw, hh / bh) * (1 - 2 * m);
  const v = { cx: (b[0] + b[2]) / 2, cy: (b[1] + b[3]) / 2, scale, w, h: hh };
  applyView(ctx, v, dpr);
  const prm = { ...defaultParams, lineweights: o.lineweights ?? false };
  if (o.color) paintItems(ctx, entries.flatMap((e) => e.items), v, prm, { colorOverride: o.color });
  else paintItems(ctx, entries.flatMap((e) => e.items), v, prm);
  if (o.highlight?.size) {
    const sel = entries.filter((e) => e.id !== null && o.highlight!.has(String(e.id)));
    if (sel.length) paintItems(ctx, sel.flatMap((e) => e.items), v, prm, { colorOverride: "#F5C518", extraWidth: 1 });
  }
  return true;
}
