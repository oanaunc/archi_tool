// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// DrawItem decoding (engine JSON of ArchiCore Render/DrawList.swift) and Canvas 2D painting that mirrors
// RenderScene in the Mac CanvasView.swift: fills under strokes (even-odd), strokes with plotted lineweights,
// points, text (greeked when tiny) and images.
export type P = [number, number];
export interface Stroke { type: "stroke"; points: P[]; closed: boolean; color: string; lineweight: number; dash: number[] }
export interface Fill { type: "fill"; loops: P[][]; color: string }
export interface Text {
  type: "text"; position: P; height: number; rotation: number; content: string; halign: string; valign: string;
  width: number; font: string; color: string;
}
export interface Img { type: "image"; path: string; origin: P; size: P; rotation: number }
export type Item = Stroke | Fill | Text | Img;
export interface Entry { id: string | null; items: Item[]; bounds: [number, number, number, number] }

function pt(v: any): P {
  if (Array.isArray(v)) return [Number(v[0]), Number(v[1])];
  if (v && typeof v === "object") return [Number(v.x ?? 0), Number(v.y ?? 0)];
  return [0, 0];
}
/** Accepts "#rrggbb", "#rrggbbaa", "rgba(...)" or {r,g,b,a} (0…1). Returns a CSS colour. */
export function color(c: any, fallback = "#ffffff", alpha?: number): string {
  if (typeof c === "string" && alpha !== undefined && alpha < 1 && /^#[0-9a-f]{6}$/i.test(c)) c = c + Math.round(Math.max(0, alpha) * 255).toString(16).padStart(2, "0");
  if (typeof c === "string") {
    if (/^#[0-9a-f]{8}$/i.test(c)) {
      const a = parseInt(c.slice(7, 9), 16) / 255;
      return `rgba(${parseInt(c.slice(1, 3), 16)},${parseInt(c.slice(3, 5), 16)},${parseInt(c.slice(5, 7), 16)},${a.toFixed(3)})`;
    }
    return c;
  }
  if (c && typeof c === "object" && "r" in c) {
    const f = (v: number) => Math.round(Math.max(0, Math.min(1, v)) * 255);
    return `rgba(${f(c.r)},${f(c.g)},${f(c.b)},${c.a ?? 1})`;
  }
  return fallback;
}

/** Decodes one DrawItem in any of the encodings the engine may use: {type:"stroke",…}, {kind:…} or Swift's {"stroke":{…}}. */
export function decodeItem(raw: any): Item | null {
  if (!raw || typeof raw !== "object") return null;
  let type: string = raw.type ?? raw.kind;
  let v = raw;
  if (!type) {
    for (const k of ["stroke", "fill", "text", "image"]) if (k in raw && typeof raw[k] === "object") { type = k; v = raw[k]; break; }
  }
  switch (type) {
    case "stroke": {
      const st = v.style ?? v;
      return { type: "stroke", points: (v.points ?? []).map(pt), closed: !!v.closed, color: color(st.color, "#ffffff", st.alpha ?? v.alpha), lineweight: Number(st.lineweight ?? 0.25), dash: (st.dash ?? []).map(Number) };
    }
    case "fill":
      return { type: "fill", loops: (v.loops ?? (v.points ? [v.points] : [])).map((l: any[]) => l.map(pt)), color: color(v.color, "rgba(255,255,255,0.1)", v.alpha) };
    case "text": {
      const t = v.text ?? v._0 ?? v;
      return {
        type: "text", position: pt(t.position), height: Number(t.height ?? 2.5), rotation: Number(t.rotation ?? 0), content: String(t.content ?? ""),
        halign: String(t.halign ?? "left"), valign: String(t.valign ?? "baseline"), width: Number(t.width ?? 0),
        font: String(v.font ?? t.style ?? "Standard"), color: color(v.color, "#ffffff", v.alpha),
      };
    }
    case "image": {
      const im = v.image ?? v._0 ?? v;
      return { type: "image", path: String(im.path ?? ""), origin: pt(im.origin), size: pt(im.size), rotation: Number(im.rotation ?? 0) };
    }
  }
  return null;
}

export function bounds(items: Item[]): [number, number, number, number] {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  const add = (p: P) => { if (p[0] < x0) x0 = p[0]; if (p[0] > x1) x1 = p[0]; if (p[1] < y0) y0 = p[1]; if (p[1] > y1) y1 = p[1]; };
  for (const it of items) {
    if (it.type === "stroke") it.points.forEach(add);
    else if (it.type === "fill") it.loops.forEach((l) => l.forEach(add));
    else if (it.type === "text") { const w = textWidthEstimate(it); add(it.position); add([it.position[0] + w * Math.cos(it.rotation), it.position[1] + w * Math.sin(it.rotation)]); add([it.position[0] - it.height * Math.sin(it.rotation), it.position[1] + it.height * Math.cos(it.rotation)]); }
    else if (it.type === "image") { add(it.origin); add([it.origin[0] + it.size[0], it.origin[1] + it.size[1]]); }
  }
  return [x0, y0, x1, y1];
}
function textWidthEstimate(t: Text) { return Math.max(...t.content.split("\n").map((l) => l.length)) * t.height * 0.75; }

/** Decodes a view.drawList result: {items:[…]} (items may carry id), {entries:[{id, items}]} or a bare array. */
export function decodeDrawList(res: any): Entry[] {
  const out: Entry[] = [];
  const list = Array.isArray(res) ? res : res?.entries ?? res?.items ?? [];
  const byId = new Map<string, Entry>();
  for (const raw of list) {
    if (raw && Array.isArray(raw.items)) {
      const items = raw.items.map(decodeItem).filter(Boolean) as Item[];
      out.push({ id: raw.id != null ? String(raw.id) : null, items, bounds: bounds(items) });
      continue;
    }
    const it = decodeItem(raw);
    if (!it) continue;
    const id = raw.id ?? raw.entity ?? raw.entityId;
    if (id != null) {
      let e = byId.get(String(id));
      if (!e) { e = { id: String(id), items: [], bounds: [0, 0, 0, 0] }; byId.set(String(id), e); out.push(e); }
      e.items.push(it);
    } else out.push({ id: null, items: [it], bounds: [0, 0, 0, 0] });
  }
  for (const e of out) e.bounds = bounds(e.items);
  return out;
}

// ---- painting ----
export interface View { cx: number; cy: number; scale: number; w: number; h: number; twist?: number }
export interface Params { lineweights: boolean; lwScale: number; minWidth: number; maxWidth: number }
export const defaultParams: Params = { lineweights: true, lwScale: 3.2, minWidth: 0.5, maxWidth: 8 };
export function lineWidth(p: Params, lw: number) { return p.lineweights ? Math.min(p.maxWidth, Math.max(p.minWidth, lw * p.lwScale)) : p.minWidth; }

/** Applies the world→screen transform (y up) to the context. */
export function applyView(ctx: CanvasRenderingContext2D, v: View, dpr: number) {
  ctx.setTransform(dpr * v.scale, 0, 0, -dpr * v.scale, dpr * (v.w / 2 - v.cx * v.scale), dpr * (v.h / 2 + v.cy * v.scale));
}

const CAP = 0.717; // Helvetica/Arial cap height per em: TextGeom.height is the cap height.
const FONT_MAP: Record<string, string> = { helvetica: "Arial", standard: "Arial", txt: "Arial", simplex: "Arial", romans: "Arial", isocp: "Arial" };
export function cssFont(name: string) {
  const n = name.toLowerCase().replace(/\.(ttf|shx)$/, "");
  return FONT_MAP[n] ? `${FONT_MAP[n]}, "Helvetica Neue", Helvetica, sans-serif` : `"${name.replace(/\.(ttf|shx)$/i, "")}", Arial, Helvetica, sans-serif`;
}

const images = new Map<string, HTMLImageElement | null>();
export let imageUrl: (path: string) => string = (p) => p;
export function setImageUrlResolver(f: (p: string) => string) { imageUrl = f; }
export let onImageLoaded: () => void = () => {};
export function setImageLoadedCallback(f: () => void) { onImageLoaded = f; }

function path(ctx: CanvasRenderingContext2D, pts: P[], closed: boolean) {
  if (!pts.length) return;
  ctx.moveTo(pts[0][0], pts[0][1]);
  for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
  if (closed) ctx.closePath();
}

export interface PaintOptions { colorOverride?: string; extraWidth?: number; dashed?: boolean; fillAlpha?: number; noText?: boolean }

/** Paints items in the Mac order (fills, strokes, points, text, images). Context must already carry the view transform. */
export function paintItems(ctx: CanvasRenderingContext2D, items: Item[], v: View, prm: Params, o: PaintOptions = {}) {
  const s = v.scale;
  for (const it of items) if (it.type === "fill") {
    ctx.beginPath(); it.loops.forEach((l) => path(ctx, l, true));
    if (o.colorOverride) { ctx.globalAlpha = o.fillAlpha ?? 0.25; ctx.fillStyle = o.colorOverride; } else ctx.fillStyle = it.color;
    ctx.fill("evenodd"); ctx.globalAlpha = 1;
  }
  ctx.lineJoin = "round";
  for (const it of items) if (it.type === "stroke" && it.points.length > 1) {
    const wPts = (o.colorOverride ? lineWidth(prm, 0.25) : lineWidth(prm, it.lineweight)) + (o.extraWidth ?? 0);
    ctx.beginPath(); path(ctx, it.points, it.closed);
    ctx.lineWidth = wPts / s;
    ctx.strokeStyle = o.colorOverride ?? it.color;
    if (o.dashed) { ctx.lineCap = "butt"; ctx.setLineDash([6 / s, 3 / s]); }
    else if (it.dash.length && it.dash.reduce((a, b) => a + Math.abs(b), 0) * s >= 4) { ctx.lineCap = "butt"; ctx.setLineDash(it.dash.map((d) => (d === 0 ? Math.max(wPts / s, 1 / s) : Math.abs(d)))); }
    else { ctx.lineCap = wPts <= 2 ? "butt" : "round"; ctx.setLineDash([]); }
    ctx.stroke();
  }
  ctx.setLineDash([]);
  for (const it of items) if (it.type === "stroke" && it.points.length === 1) {
    const r = (o.colorOverride ? 2.5 : 1.6) / s;
    ctx.fillStyle = o.colorOverride ?? it.color;
    ctx.beginPath(); ctx.arc(it.points[0][0], it.points[0][1], r, 0, Math.PI * 2); ctx.fill();
  }
  if (!o.noText) for (const it of items) if (it.type === "text") paintText(ctx, it, s, o.colorOverride);
  for (const it of items) if (it.type === "image") paintImage(ctx, it, s, o.colorOverride);
}

export function paintText(ctx: CanvasRenderingContext2D, t: Text, s: number, override?: string) {
  const screenH = t.height * s;
  if (screenH < 1.2 || !t.content) return;
  const fontPx = screenH / CAP;
  ctx.save();
  // Go to screen-sized, y-down text space at the insertion point.
  ctx.translate(t.position[0], t.position[1]);
  ctx.rotate(t.rotation);
  ctx.scale(1 / s, -1 / s);
  const lines = t.content.replace(/\\P/g, "\n").split("\n");
  const lh = screenH * 1.667;
  ctx.font = `${fontPx}px ${cssFont(t.font)}`;
  const widths = lines.map((l) => ctx.measureText(l).width);
  const align = t.halign === "right" ? 1 : t.halign === "center" || t.halign === "middle" || t.halign === "aligned" || t.halign === "fit" ? 0.5 : 0;
  // Baseline of the first line relative to the insertion point (y down).
  let y0 = 0;
  const total = (lines.length - 1) * lh;
  if (t.valign === "middle" || t.halign === "middle") y0 = screenH / 2 - total / 2;
  else if (t.valign === "top") y0 = screenH;
  else if (t.valign === "bottom") y0 = -fontPx * 0.212 - total;
  else y0 = lines.length > 1 && t.width > 0 ? screenH : -total * 0; // multiline text anchors at the top of the first line
  if (screenH < 3.5) {
    ctx.globalAlpha = 0.35; ctx.fillStyle = override ?? t.color;
    lines.forEach((_, i) => ctx.fillRect(-widths[i] * align, y0 + i * lh - screenH, widths[i], screenH));
  } else {
    ctx.fillStyle = override ?? t.color;
    ctx.textBaseline = "alphabetic";
    lines.forEach((l, i) => ctx.fillText(l, -widths[i] * align, y0 + i * lh));
  }
  ctx.restore();
}

function paintImage(ctx: CanvasRenderingContext2D, im: Img, s: number, override?: string) {
  let img = images.get(im.path);
  if (img === undefined) {
    const el = new Image();
    images.set(im.path, null);
    el.onload = () => { images.set(im.path, el); onImageLoaded(); };
    el.src = imageUrl(im.path);
  }
  ctx.save();
  ctx.translate(im.origin[0], im.origin[1]);
  ctx.rotate(im.rotation);
  if (img && !override) {
    ctx.scale(1, -1);
    ctx.drawImage(img, 0, -im.size[1], im.size[0], im.size[1]);
  } else {
    ctx.strokeStyle = override ?? "#ff453a"; ctx.lineWidth = (override ? 1.5 : 1) / s;
    ctx.strokeRect(0, 0, im.size[0], im.size[1]);
    if (!override) { ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(im.size[0], im.size[1]); ctx.moveTo(0, im.size[1]); ctx.lineTo(im.size[0], 0); ctx.stroke(); }
  }
  ctx.restore();
}

// ---- hit testing (hover highlight and local window selection) ----
function segDist(q: P, a: P, b: P) {
  const dx = b[0] - a[0], dy = b[1] - a[1];
  const l2 = dx * dx + dy * dy;
  let t = l2 ? ((q[0] - a[0]) * dx + (q[1] - a[1]) * dy) / l2 : 0;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(q[0] - a[0] - t * dx, q[1] - a[1] - t * dy);
}
function inPoly(q: P, l: P[]) {
  let c = false;
  for (let i = 0, j = l.length - 1; i < l.length; j = i++) {
    if ((l[i][1] > q[1]) !== (l[j][1] > q[1]) && q[0] < ((l[j][0] - l[i][0]) * (q[1] - l[i][1])) / (l[j][1] - l[i][1]) + l[i][0]) c = !c;
  }
  return c;
}
export function distance(e: Entry, q: P, tol: number): number {
  const b = e.bounds;
  if (q[0] < b[0] - tol || q[0] > b[2] + tol || q[1] < b[1] - tol || q[1] > b[3] + tol) return Infinity;
  let best = Infinity;
  for (const it of e.items) {
    if (it.type === "stroke") {
      const p = it.points;
      if (p.length === 1) best = Math.min(best, Math.hypot(q[0] - p[0][0], q[1] - p[0][1]));
      for (let i = 0; i + 1 < p.length; i++) best = Math.min(best, segDist(q, p[i], p[i + 1]));
      if (it.closed && p.length > 2) best = Math.min(best, segDist(q, p[p.length - 1], p[0]));
    } else if (it.type === "text") {
      const [x0, y0, x1, y1] = bounds([it]);
      if (q[0] >= x0 && q[0] <= x1 && q[1] >= y0 && q[1] <= y1) return 0;
    }
  }
  if (best > tol) for (const it of e.items) if (it.type === "fill" && it.loops.some((l) => inPoly(q, l))) return tol * 0.99; // fills pick after strokes
  return best;
}
export function pick(entries: Entry[], q: P, tol: number): Entry | null {
  let best: Entry | null = null, bd = tol;
  for (const e of entries) {
    if (e.id == null) continue;
    const d = distance(e, q, tol);
    if (d <= bd) { bd = d; best = e; }
  }
  return best;
}
