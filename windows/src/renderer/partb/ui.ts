// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Tool windows (the Mac NSPanel / NSWindow tool windows), sheets (modal dialogs such as TitleBlockSheet and
// ConnectClaudeSheet) and the controls of Theme.swift: FlatButtonStyle (prominent / compact), IconButton, darkField,
// PanelHeader, HSeparator, segmented pickers, sliders, switches and pop-up menus, with the dark theme and #F5C518 accent.
import "./partb.css";
import { h, clear } from "../dom";
import { icon, hasIcon } from "../icons";
import { help, showMenu, type MenuItem } from "../ui/menu";

export { h, clear, help, showMenu };
export type { MenuItem };

// ---- icons (Lucide, ISC) for SF Symbols the generated table does not have ----
const SVGNS = "http://www.w3.org/2000/svg";
const EXTRA: Record<string, [string, Record<string, string>][]> = {
  "folder.badge.plus": [["path", { d: "M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z" }], ["path", { d: "M12 10v6" }], ["path", { d: "M9 13h6" }]],
  "questionmark.square.dashed": [["rect", { x: "3", y: "3", width: "18", height: "18", rx: "2", "stroke-dasharray": "3 3" }], ["path", { d: "M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3" }], ["path", { d: "M12 17h.01" }]],
  "play.fill": [["polygon", { points: "6 3 20 12 6 21 6 3", fill: "currentColor" }]],
  play: [["polygon", { points: "6 3 20 12 6 21 6 3" }]],
  book: [["path", { d: "M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H19a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H6.5a1 1 0 0 1 0-5H20" }]],
  "arrow.up": [["path", { d: "m5 12 7-7 7 7" }], ["path", { d: "M12 19V5" }]],
  "arrow.down": [["path", { d: "M12 5v14" }], ["path", { d: "m19 12-7 7-7-7" }]],
  "minus.circle": [["circle", { cx: "12", cy: "12", r: "10" }], ["path", { d: "M8 12h8" }]],
  "checkmark.circle.fill": [["circle", { cx: "12", cy: "12", r: "10", fill: "currentColor" }], ["path", { d: "m9 12 2 2 4-4", stroke: "#26272B" }]],
  "exclamationmark.bubble.fill": [["path", { d: "M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z", fill: "currentColor" }], ["path", { d: "M12 7v3", stroke: "#26272B" }], ["path", { d: "M12 13h.01", stroke: "#26272B" }]],
  "arrow.right.circle": [["circle", { cx: "12", cy: "12", r: "10" }], ["path", { d: "M8 12h8" }], ["path", { d: "m12 16 4-4-4-4" }]],
  "video.badge.plus": [["path", { d: "m16 13 5.2 3.5a.5.5 0 0 0 .8-.4V7.9a.5.5 0 0 0-.8-.4L16 10.5" }], ["rect", { x: "2", y: "6", width: "14", height: "12", rx: "2" }], ["path", { d: "M9 9v6" }], ["path", { d: "M6 12h6" }]],
  "star.fill": [["polygon", { points: "12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2", fill: "currentColor" }]],
};
export function ico(sf: string, size = 13, stroke = 1.7): SVGSVGElement {
  if (EXTRA[sf] && (!hasIcon(sf) || sf === "star.fill")) {
    const svg = document.createElementNS(SVGNS, "svg");
    for (const [k, v] of Object.entries({ viewBox: "0 0 24 24", width: String(size), height: String(size), fill: "none", stroke: "currentColor", "stroke-width": String(stroke), "stroke-linecap": "round", "stroke-linejoin": "round" })) svg.setAttribute(k, v);
    svg.classList.add("icon");
    svg.dataset.sf = sf;
    for (const [tag, attrs] of EXTRA[sf]) { const el = document.createElementNS(SVGNS, tag); for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v); svg.append(el); }
    return svg;
  }
  return icon(sf, size, stroke);
}

// ---- storage (per-user settings the Mac keeps in UserDefaults) ----
export function load<T>(key: string, def: T): T { try { const v = localStorage.getItem("archi.b." + key); return v === null ? def : JSON.parse(v); } catch { return def; } }
export function store(key: string, v: unknown) { try { localStorage.setItem("archi.b." + key, JSON.stringify(v)); } catch {} }

// ---- controls ----
export interface BtnOpts { prominent?: boolean; compact?: boolean; icon?: string; help?: string; disabled?: boolean; onClick?: () => void; cls?: string }
export function button(title: string, o: BtnOpts = {}): HTMLButtonElement {
  const b = h("button", { class: `pb-btn${o.prominent ? " prominent" : ""}${o.compact ? " compact" : ""}${o.cls ? " " + o.cls : ""}` }, o.icon ? ico(o.icon, 12) : null, title ? h("span", { text: title }) : null) as HTMLButtonElement;
  b.disabled = !!o.disabled;
  if (o.help) help(b, o.help);
  if (o.onClick) b.addEventListener("click", () => { if (!b.disabled) o.onClick!(); });
  return b;
}
export function iconButton(symbol: string, tip: string, onClick: () => void, o: { active?: boolean; disabled?: boolean; size?: number } = {}): HTMLButtonElement {
  const b = h("button", { class: "pb-ibtn" + (o.active ? " active" : "") }, ico(symbol, o.size ?? 12, 1.8)) as HTMLButtonElement;
  b.disabled = !!o.disabled;
  help(b, tip);
  b.addEventListener("click", (e) => { e.stopPropagation(); if (!b.disabled) onClick(); });
  return b;
}
export interface FieldOpts { value?: string; placeholder?: string; width?: number; mono?: boolean; onInput?: (v: string) => void; onCommit?: (v: string) => void; flex?: boolean; type?: string; title?: string }
/** darkField text field: onCommit fires on Enter and when focus leaves after a change (SwiftUI onSubmit / bindings). */
export function field(o: FieldOpts = {}): HTMLInputElement {
  const f = h("input", { class: "pb-field" + (o.mono ? " mono" : ""), type: o.type ?? "text", placeholder: o.placeholder ?? "", spellcheck: false }) as HTMLInputElement;
  f.value = o.value ?? "";
  if (o.width) f.style.width = o.width + "px";
  if (o.flex) f.style.flex = "1";
  if (o.title) help(f, o.title);
  let committed = f.value;
  f.addEventListener("input", () => o.onInput?.(f.value));
  const commit = () => { if (f.value !== committed) { committed = f.value; o.onCommit?.(f.value); } };
  f.addEventListener("keydown", (e) => { e.stopPropagation(); if (e.key === "Enter") { commit(); } else if (e.key === "Escape") { f.value = committed; f.blur(); } });
  f.addEventListener("blur", commit);
  return f;
}
/** Number field (SwiftUI TextField with .number format): commits a parsed number. */
export function numberField(value: number | null | undefined, onCommit: (v: number) => void, o: { width?: number; decimals?: number; placeholder?: string } = {}): HTMLInputElement {
  const fmtNum = (v: number | null | undefined) => v === null || v === undefined || !isFinite(v) ? "" : String(Number(v.toFixed(o.decimals ?? 4)));
  const f = field({ value: fmtNum(value), width: o.width ?? 70, placeholder: o.placeholder, onCommit: (s) => { const v = Number(s.replace(",", ".")); if (s.trim() !== "" && isFinite(v)) onCommit(v); else f.value = fmtNum(value); } });
  return f;
}
export function textArea(value: string, onCommit: (v: string) => void, rows = 3): HTMLTextAreaElement {
  const t = h("textarea", { class: "pb-field", rows, spellcheck: false }) as HTMLTextAreaElement;
  t.value = value;
  t.addEventListener("keydown", (e) => e.stopPropagation());
  t.addEventListener("change", () => onCommit(t.value));
  return t;
}
export function slider(value: number, min: number, max: number, o: { step?: number; onInput?: (v: number) => void; onChange?: (v: number) => void; disabled?: boolean } = {}): HTMLInputElement {
  const s = h("input", { class: "pb-slider", type: "range" }) as HTMLInputElement;
  s.min = String(min); s.max = String(max); s.step = String(o.step ?? ((max - min) / 1000 || 0.001)); s.value = String(value);
  s.disabled = !!o.disabled;
  s.addEventListener("input", () => o.onInput?.(Number(s.value)));
  s.addEventListener("change", () => o.onChange?.(Number(s.value)));
  s.addEventListener("keydown", (e) => e.stopPropagation());
  return s;
}
export function segmented<T extends string>(options: T[], value: T, onChange: (v: T) => void, labels?: Record<string, string>): HTMLElement {
  const el = h("div", { class: "pb-seg" });
  const render = (v: T) => {
    clear(el);
    for (const o of options) {
      const b = h("button", { class: o === v ? "sel" : "", text: labels?.[o] ?? o });
      b.addEventListener("click", () => { if (o !== v) { render(o); onChange(o); } });
      el.append(b);
    }
  };
  render(value);
  return el;
}
export function picker(options: (string | { value: string; label: string })[], value: string, onChange: (v: string) => void, width?: number): HTMLSelectElement {
  const s = h("select", { class: "pb-field" }) as HTMLSelectElement;
  for (const o of options) {
    const v = typeof o === "string" ? o : o.value, l = typeof o === "string" ? o : o.label;
    const op = h("option", { value: v, text: l }) as HTMLOptionElement;
    s.append(op);
  }
  s.value = value;
  if (width) s.style.width = width + "px";
  s.addEventListener("change", () => onChange(s.value));
  s.addEventListener("keydown", (e) => e.stopPropagation());
  return s;
}
export function checkbox(label: string, value: boolean, onChange: (v: boolean) => void, tip?: string): HTMLElement {
  const i = h("input", { type: "checkbox" }) as HTMLInputElement;
  i.checked = value;
  i.addEventListener("change", () => onChange(i.checked));
  const l = h("label", { class: "pb-check" }, i, label ? h("span", { text: label }) : null);
  if (tip) help(l, tip);
  return l;
}
/** SwiftUI .toggleStyle(.switch) (mini). */
export function toggleSwitch(label: string, value: boolean, onChange: (v: boolean) => void, tip?: string): HTMLElement {
  let on = value;
  const sw = h("span", { class: "pb-switch" + (on ? " on" : "") });
  const el = h("label", { class: "pb-check", role: "switch" }, label ? h("span", { text: label }) : null, sw);
  el.setAttribute("aria-checked", String(on));
  el.addEventListener("click", () => { on = !on; sw.classList.toggle("on", on); el.setAttribute("aria-checked", String(on)); onChange(on); });
  if (tip) help(el, tip);
  return el;
}
export function colorWell(hex: string, onChange: (hex: string) => void): HTMLInputElement {
  const c = h("input", { class: "pb-color", type: "color" }) as HTMLInputElement;
  c.value = normHex(hex);
  c.addEventListener("change", () => onChange(c.value.toUpperCase()));
  return c;
}
export function menuButton(label: string | Element, symbol: string | null, items: () => MenuItem[], tip?: string): HTMLButtonElement {
  const b = h("button", { class: "pb-menubtn" }, symbol ? ico(symbol, 12) : null, typeof label === "string" ? h("span", { text: label }) : label, h("span", { class: "chev" }, ico("chevron.down", 8, 2))) as HTMLButtonElement;
  if (tip) help(b, tip);
  b.addEventListener("click", (e) => { e.stopPropagation(); showMenu(items(), b); });
  return b;
}
export function header(text: string): HTMLElement { return h("div", { class: "pb-header", text }); }
export function hsep(): HTMLElement { return h("div", { class: "pb-hsep" }); }
export function vsep(): HTMLElement { return h("div", { class: "pb-vsep" }); }
export function row(...kids: (Node | string | null | undefined | false)[]): HTMLElement { return h("div", { class: "pb-row" }, ...kids); }
export function col(...kids: (Node | string | null | undefined | false)[]): HTMLElement { return h("div", { class: "pb-col" }, ...kids); }
export function spacer(): HTMLElement { return h("div", { class: "pb-spacer" }); }
export function text(t: string, cls = ""): HTMLElement { return h("span", { class: cls, text: t }); }
export function labeled(label: string, ...kids: (Node | null)[]): HTMLElement { return row(h("span", { class: "pb-label", text: label }), ...kids); }

// ---- colours ----
export function normHex(s: string): string {
  const t = (s || "").replace(/[^0-9a-f]/gi, "");
  if (t.length === 3) return "#" + t.split("").map((c) => c + c).join("").toLowerCase();
  return "#" + (t + "000000").slice(0, 6).toLowerCase();
}
export function rgbaToHex(c: { r: number; g: number; b: number } | undefined): string {
  if (!c) return "#cccccc";
  const b = (v: number) => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0");
  return "#" + b(c.r) + b(c.g) + b(c.b);
}
export function hexToRgba(hex: string, a = 1) {
  const t = normHex(hex).slice(1);
  return { r: parseInt(t.slice(0, 2), 16) / 255, g: parseInt(t.slice(2, 4), 16) / 255, b: parseInt(t.slice(4, 6), 16) / 255, a };
}
export const fmt = (v: number, d = 2) => { if (!isFinite(v)) return "—"; const s = v.toFixed(d); return s.includes(".") ? s.replace(/\.?0+$/, "") : s; };

// ---- tool windows ----
interface Frame { x: number; y: number; w: number; h: number }
const open = new Map<string, ToolWindow>();
let zTop = 310;

export class ToolWindow {
  el: HTMLElement;
  body: HTMLElement;
  private titleEl: HTMLElement;
  onClose: (() => void) | null = null;

  /** Shows the window with this key (reusing it when open, like the Mac `if let w = window { … makeKeyAndOrderFront }`). */
  static show(key: string, title: string, size: { w: number; h: number; minW?: number; minH?: number }, build: (w: ToolWindow) => void): ToolWindow {
    let w = open.get(key);
    if (!w) { w = new ToolWindow(key, title, size); open.set(key, w); }
    else w.setTitle(title);
    clear(w.body);
    build(w);
    w.front();
    return w;
  }
  static get(key: string) { return open.get(key) ?? null; }
  static isOpen(key: string) { return open.has(key); }
  static closeAll() { for (const w of [...open.values()]) w.close(); }

  private constructor(readonly key: string, title: string, size: { w: number; h: number; minW?: number; minH?: number }) {
    const saved = load<Frame | null>("frame." + key, null);
    const f: Frame = saved ?? { w: size.w, h: size.h, x: Math.max(20, (innerWidth - size.w) / 2), y: Math.max(40, (innerHeight - size.h) / 2) };
    this.titleEl = h("div", { class: "pb-title", text: title });
    const close = h("button", { class: "pb-close" }, ico("xmark", 10, 2));
    help(close, "Close");
    close.addEventListener("click", () => this.close());
    const bar = h("div", { class: "pb-titlebar" }, this.titleEl, close);
    this.body = h("div", { class: "pb-body" });
    const grip = h("div", { class: "pb-grip" });
    this.el = h("div", { class: "pb-win", role: "dialog", "aria-label": title, "data-window": key }, bar, this.body, grip);
    this.el.style.minWidth = (size.minW ?? Math.min(size.w, 320)) + "px";
    this.el.style.minHeight = (size.minH ?? Math.min(size.h, 200)) + "px";
    this.place(f);
    document.body.append(this.el);
    this.el.addEventListener("mousedown", () => this.front(), true);
    this.el.addEventListener("keydown", (e) => { e.stopPropagation(); if (e.key === "Escape" && (e.target as HTMLElement).tagName !== "INPUT" && (e.target as HTMLElement).tagName !== "TEXTAREA") this.close(); });
    bar.addEventListener("mousedown", (e) => {
      if ((e.target as HTMLElement).closest(".pb-close")) return;
      const x0 = e.clientX, y0 = e.clientY, r = this.el.getBoundingClientRect();
      const mv = (ev: MouseEvent) => this.place({ x: r.left + ev.clientX - x0, y: r.top + ev.clientY - y0, w: r.width, h: r.height });
      const up = () => { removeEventListener("mousemove", mv); removeEventListener("mouseup", up); this.saveFrame(); };
      addEventListener("mousemove", mv); addEventListener("mouseup", up);
      e.preventDefault();
    });
    grip.addEventListener("mousedown", (e) => {
      const x0 = e.clientX, y0 = e.clientY, r = this.el.getBoundingClientRect();
      const mv = (ev: MouseEvent) => this.place({ x: r.left, y: r.top, w: r.width + ev.clientX - x0, h: r.height + ev.clientY - y0 });
      const up = () => { removeEventListener("mousemove", mv); removeEventListener("mouseup", up); this.saveFrame(); };
      addEventListener("mousemove", mv); addEventListener("mouseup", up);
      e.preventDefault(); e.stopPropagation();
    });
  }
  private place(f: Frame) {
    const w = Math.max(240, Math.min(f.w, innerWidth - 8)), hh = Math.max(140, Math.min(f.h, innerHeight - 8));
    const x = Math.max(-w + 80, Math.min(f.x, innerWidth - 80)), y = Math.max(0, Math.min(f.y, innerHeight - 30));
    Object.assign(this.el.style, { left: x + "px", top: y + "px", width: w + "px", height: hh + "px" });
  }
  private saveFrame() { const r = this.el.getBoundingClientRect(); store("frame." + this.key, { x: r.left, y: r.top, w: r.width, h: r.height }); }
  setTitle(t: string) { this.titleEl.textContent = t; this.el.setAttribute("aria-label", t); }
  front() { this.el.style.zIndex = String(++zTop); for (const w of open.values()) w.el.classList.toggle("inactive", w !== this); }
  close() { open.delete(this.key); this.el.remove(); this.onClose?.(); }
}

// ---- sheets (modal) ----
export class Sheet {
  el: HTMLElement;
  overlay: HTMLElement;
  body: HTMLElement;
  constructor(width: number, o: { onCancel?: () => void } = {}) {
    this.body = h("div", { class: "pb-col", style: { gap: "0", flex: "1", minHeight: "0" } });
    this.el = h("div", { class: "pb-sheet", role: "dialog", style: { width: width + "px" } }, this.body);
    this.overlay = h("div", { class: "pb-sheet-overlay" }, this.el);
    this.overlay.addEventListener("keydown", (e) => { e.stopPropagation(); if (e.key === "Escape") { this.close(); o.onCancel?.(); } });
    this.overlay.addEventListener("mousedown", (e) => { if (e.target === this.overlay) e.preventDefault(); });
    document.body.append(this.overlay);
  }
  close() { this.overlay.remove(); }
}

/** A modal prompt with one text field (the Mac NSAlert with an accessory text field). */
export function promptText(title: string, message: string, value: string, ok = "Save"): Promise<string | null> {
  return new Promise((resolve) => {
    const s = new Sheet(360, { onCancel: () => resolve(null) });
    const f = field({ value, flex: true });
    const done = (v: string | null) => { s.close(); resolve(v); };
    f.addEventListener("keydown", (e) => { if (e.key === "Enter") done(f.value); });
    s.body.append(h("div", { class: "pb-sheet-head", text: title }),
      h("div", { class: "pb-col", style: { padding: "0 14px 6px" } }, message ? h("div", { class: "pb-dim", text: message }) : null, f),
      h("div", { class: "pb-sheet-foot" }, button("Cancel", { onClick: () => done(null) }), button(ok, { prominent: true, onClick: () => done(f.value) })));
    setTimeout(() => { f.focus(); f.select(); }, 0);
  });
}
export function alertBox(title: string, message: string): Promise<void> {
  return new Promise((resolve) => {
    const s = new Sheet(380, { onCancel: () => resolve() });
    s.body.append(h("div", { class: "pb-sheet-head", text: title }), h("div", { style: { padding: "0 14px 8px", whiteSpace: "pre-wrap" }, text: message }),
      h("div", { class: "pb-sheet-foot" }, button("OK", { prominent: true, onClick: () => { s.close(); resolve(); } })));
  });
}

/** Material swatch sphere (MaterialSwatch): base colour or texture, a specular highlight by roughness, darker rim by metalness. */
export function swatch(m: { color?: any; roughness?: number; metalness?: number; transparency?: number; texture?: string | null }, size: number, textureUrl?: string | null): HTMLElement {
  const c = rgbaToHex(m.color);
  const r = m.roughness ?? 0.8, mt = m.metalness ?? 0;
  const el = h("div", { class: "pb-swatch", style: { width: size + "px", height: size + "px", opacity: String(1 - (m.transparency ?? 0) * 0.6) } });
  const hl = `radial-gradient(circle at 32% 28%, rgba(255,255,255,${(0.85 * (1 - r) + 0.1).toFixed(3)}) 0, rgba(255,255,255,0) ${size * 0.45}px)`;
  const rim = `radial-gradient(circle at 40% 35%, rgba(0,0,0,0) ${size * 0.2}px, rgba(0,0,0,${(0.45 + 0.2 * mt).toFixed(3)}) ${size * 0.7}px)`;
  el.style.background = `${hl}, ${rim}, ${textureUrl ? `url("${textureUrl}") center/cover` : c}`;
  return el;
}
