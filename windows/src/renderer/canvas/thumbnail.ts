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
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const e of entries) { x0 = Math.min(x0, e.bounds[0]); y0 = Math.min(y0, e.bounds[1]); x1 = Math.max(x1, e.bounds[2]); y1 = Math.max(y1, e.bounds[3]); }
  const items = entries.flatMap((e) => e.items);
  let painted = "";
  const paint = () => {
    const w = host.clientWidth, hh = host.clientHeight, dpr = devicePixelRatio || 1;
    if (!w || !hh || painted === `${w}x${hh}@${dpr}`) return;
    painted = `${w}x${hh}@${dpr}`;
    cv.width = Math.round(w * dpr); cv.height = Math.round(hh * dpr);
    // DocumentThumbnails.render: the plan fitted into a 320×200 picture with an 8 % margin, shown with
    // ThumbnailView's aspect-fill (the picture covers the card's thumbnail box and is cropped, centred).
    const bw = Math.max(x1 - x0, 1e-9), bh = Math.max(y1 - y0, 1e-9);
    const scale = Math.max(w / THUMB_W, hh / THUMB_H) * Math.min(THUMB_W * (1 - 2 * THUMB_MARGIN) / bw, THUMB_H * (1 - 2 * THUMB_MARGIN) / bh);
    const v = { cx: (x0 + x1) / 2, cy: (y0 + y1) / 2, scale, w, h: hh };
    const ctx = cv.getContext("2d")!;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = "#1E1F22"; ctx.fillRect(0, 0, cv.width, cv.height);
    applyView(ctx, v, dpr);
    paintItems(ctx, items, v, { ...defaultParams, lineweights: false });
  };
  // Paint once the card has its size (the start screen may still be hidden or laying out), and again when it changes.
  new ResizeObserver(paint).observe(host);
  requestAnimationFrame(paint);
}

/** Size and margin of the Mac's plan thumbnail picture (DocumentThumbnails.render). */
export const THUMB_W = 320, THUMB_H = 200, THUMB_MARGIN = 0.08;
