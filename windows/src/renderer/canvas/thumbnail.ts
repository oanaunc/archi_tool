// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Plan thumbnails for the start screen: paints a DrawList (bundled <name>.thumb.json) fitted into a card.
import { decodeDrawList, paintItems, applyView, defaultParams } from "./drawitems";
import { icon } from "../icons";

export async function paintThumbnail(host: HTMLElement, url: string, fallbackSymbol: string) {
  let data: any = null;
  try { const r = await fetch(url); if (r.ok) data = await r.json(); } catch {}
  const entries = data ? decodeDrawList(data) : [];
  if (!entries.length) { host.append(icon(fallbackSymbol, 24, 1.5)); return; }
  const cv = document.createElement("canvas");
  host.append(cv);
  requestAnimationFrame(() => {
    const w = host.clientWidth || 260, hh = host.clientHeight || 100, dpr = devicePixelRatio || 1;
    cv.width = w * dpr; cv.height = hh * dpr;
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const e of entries) { x0 = Math.min(x0, e.bounds[0]); y0 = Math.min(y0, e.bounds[1]); x1 = Math.max(x1, e.bounds[2]); y1 = Math.max(y1, e.bounds[3]); }
    const scale = Math.min(w / (x1 - x0), hh / (y1 - y0)) * 0.9;
    const v = { cx: (x0 + x1) / 2, cy: (y0 + y1) / 2, scale, w, h: hh };
    const ctx = cv.getContext("2d")!;
    ctx.fillStyle = "#1E1F22"; ctx.fillRect(0, 0, cv.width, cv.height);
    applyView(ctx, v, dpr);
    paintItems(ctx, entries.flatMap((e) => e.items), v, { ...defaultParams, lineweights: false });
  });
}
