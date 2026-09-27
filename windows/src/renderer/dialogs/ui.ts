// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Dialog building blocks with the Mac look (ArchiApp/Theme.swift, MainWindow.swift SheetFrame, Preferences.swift
// PrefSection): modal sheets under the title bar, modeless tool windows (Settings, Customize Ribbon, Keyboard &
// Mouse), flat buttons, icon buttons, dark fields, check boxes, pop-up pickers, segmented pickers, steppers, sliders,
// radio groups, and the NSAlert-style message / text-input alerts.
import "./dialogs.css";
import { h, clear } from "../dom";
import { icon } from "../icons";
import { showMenu, help, MenuItem } from "../ui/menu";

export type Child = Node | string | null | undefined | false;
export interface Option<T = string> { value: T; title: string; symbol?: string; disabled?: boolean }

/** Keys typed in a dialog never reach the command line (main.ts listens on window). */
function isolateKeys(el: HTMLElement, onKey?: (e: KeyboardEvent) => void) {
  el.addEventListener("keydown", (e) => { onKey?.(e); e.stopPropagation(); });
  el.addEventListener("keyup", (e) => e.stopPropagation());
  el.addEventListener("keypress", (e) => e.stopPropagation());
}

// ---- modal sheets (SheetFrame) ----
export interface SheetOptions {
  title: string | HTMLElement; width?: number; content: HTMLElement;
  onCancel?: (() => void) | null; onOK?: (() => void | boolean | Promise<void | boolean>) | null; okTitle?: string; cancelTitle?: string;
  /** Left side of the footer (match count, note …). */
  footerLeft?: HTMLElement | null; footerButtons?: HTMLElement[]; cls?: string;
}
export interface SheetHandle { el: HTMLElement; close(): void; ok: HTMLButtonElement | null }
const openSheets: SheetHandle[] = [];
export function anySheetOpen() { return openSheets.length > 0; }

export function sheet(o: SheetOptions): SheetHandle {
  const overlay = h("div", { class: "dlg-overlay" });
  const box = h("div", { class: "dlg sheet" + (o.cls ? " " + o.cls : ""), role: "dialog", "aria-modal": "true" });
  if (o.width) box.style.width = o.width + "px";
  const title = typeof o.title === "string" ? h("div", { class: "dlg-title", text: o.title }) : h("div", { class: "dlg-title" }, o.title);
  const okBtn = o.onOK ? flatButton(o.okTitle ?? "OK", () => void runOK(), { prominent: true }) : null;
  const buttons: HTMLElement[] = [...(o.footerButtons ?? [])];
  if (o.onCancel) buttons.push(flatButton(o.cancelTitle ?? "Cancel", () => { o.onCancel?.(); close(); }));
  if (okBtn) buttons.push(okBtn);
  box.append(title, h("div", { class: "hsep" }), h("div", { class: "dlg-body" }, o.content));
  if (buttons.length || o.footerLeft) box.append(h("div", { class: "hsep" }), h("div", { class: "dlg-footer" }, o.footerLeft ?? h("span"), h("span", { class: "spacer" }), ...buttons));
  overlay.append(box);
  const handle: SheetHandle = { el: box, close, ok: okBtn as HTMLButtonElement | null };
  async function runOK() { const r = await o.onOK?.(); if (r !== false) close(); }
  function close() { overlay.remove(); const i = openSheets.indexOf(handle); if (i >= 0) openSheets.splice(i, 1); }
  isolateKeys(overlay, (e) => {
    if (e.key === "Escape") { e.preventDefault(); if (o.onCancel) { o.onCancel(); close(); } else if (o.onOK) void runOK(); else close(); }
    else if (e.key === "Enter" && !(e.target instanceof HTMLTextAreaElement) && !(e.target instanceof HTMLButtonElement) && okBtn && !okBtn.disabled) { e.preventDefault(); void runOK(); }
  });
  document.body.append(overlay);
  openSheets.push(handle);
  requestAnimationFrame(() => { (box.querySelector("input:not([type=checkbox]):not([type=range]),button.picker,button.chk") as HTMLElement | null)?.focus(); box.classList.add("in"); });
  return handle;
}

// ---- modeless tool windows (NSWindow: Settings, Customize Ribbon, Keyboard & Mouse) ----
export interface WindowHandle { el: HTMLElement; body: HTMLElement; close(): void; focus(): void }
const windows = new Map<string, WindowHandle>();
let zTop = 800;
export function toolWindow(id: string, title: string, width: number, height: number, build: (body: HTMLElement, w: WindowHandle) => void, onClose?: () => void): WindowHandle {
  const existing = windows.get(id);
  if (existing) { existing.focus(); return existing; }
  const body = h("div", { class: "twin-body" });
  const closeBtn = h("button", { class: "twin-close", "aria-label": "Close" }, icon("xmark", 11, 2));
  const bar = h("div", { class: "twin-bar" }, h("span", { class: "twin-title", text: title }), closeBtn);
  const el = h("div", { class: "dlg twin", role: "dialog", "data-window": id }, bar, body);
  el.style.width = width + "px"; el.style.height = height + "px";
  el.style.left = Math.max(8, (innerWidth - width) / 2) + "px"; el.style.top = Math.max(40, (innerHeight - height) / 2 - 20) + "px";
  const handle: WindowHandle = {
    el, body,
    close() { el.remove(); windows.delete(id); onClose?.(); },
    focus() { el.style.zIndex = String(++zTop); el.classList.add("focused"); },
  };
  closeBtn.addEventListener("click", () => handle.close());
  bar.addEventListener("mousedown", (e) => {
    if ((e.target as HTMLElement).closest(".twin-close")) return;
    const r = el.getBoundingClientRect(), x0 = e.clientX, y0 = e.clientY;
    const mv = (ev: MouseEvent) => { el.style.left = Math.min(innerWidth - 60, Math.max(-r.width + 80, r.left + ev.clientX - x0)) + "px"; el.style.top = Math.min(innerHeight - 30, Math.max(0, r.top + ev.clientY - y0)) + "px"; };
    const up = () => { removeEventListener("mousemove", mv); removeEventListener("mouseup", up); };
    addEventListener("mousemove", mv); addEventListener("mouseup", up);
    e.preventDefault();
  });
  // Bring to front by z-index (moving the node between mousedown and mouseup would swallow the click).
  el.addEventListener("mousedown", () => { if (Number(el.style.zIndex || 0) < zTop) el.style.zIndex = String(++zTop); }, true);
  el.style.zIndex = String(++zTop);
  isolateKeys(el, (e) => { if (e.key === "Escape" && !(e.target instanceof HTMLInputElement)) { e.preventDefault(); handle.close(); } });
  windows.set(id, handle);
  document.body.append(el);
  build(body, handle);
  return handle;
}
export function windowOpen(id: string) { return windows.get(id) ?? null; }

// ---- controls ----
export function flatButton(title: string | Node, onClick: () => void, o: { prominent?: boolean; compact?: boolean; disabled?: boolean; help?: string; symbol?: string } = {}): HTMLButtonElement {
  const b = h("button", { class: "flatbtn dlgbtn" + (o.prominent ? " prominent" : "") + (o.compact ? " compact" : "") }) as HTMLButtonElement;
  if (o.symbol) b.append(icon(o.symbol, 11, 1.8));
  b.append(typeof title === "string" ? h("span", { text: title }) : title);
  b.disabled = !!o.disabled;
  if (o.help) help(b, o.help);
  b.addEventListener("click", () => { if (!b.disabled) onClick(); });
  return b;
}

export function iconButton(symbol: string, tip: string, onClick: () => void, o: { disabled?: boolean; active?: boolean } = {}): HTMLButtonElement {
  const b = h("button", { class: "iconbtn" + (o.active ? " active" : "") }, icon(symbol, 12, 1.8)) as HTMLButtonElement;
  b.disabled = !!o.disabled;
  help(b, tip);
  b.addEventListener("click", () => { if (!b.disabled) onClick(); });
  return b;
}

/** A Mac check box (Toggle in a Form / VStack). */
export function toggle(label: string, checked: boolean, onChange: (v: boolean) => void, o: { disabled?: boolean; bold?: boolean; help?: string } = {}): HTMLElement {
  const box = h("span", { class: "chkbox" }, icon("checkmark", 10, 3));
  const b = h("button", { class: "chk" + (checked ? " on" : "") + (o.bold ? " bold" : ""), role: "checkbox", "aria-checked": String(checked) }, box, h("span", { class: "lbl", text: label })) as HTMLButtonElement;
  b.disabled = !!o.disabled;
  if (o.help) help(b, o.help);
  b.addEventListener("click", () => {
    if (b.disabled) return;
    const v = !b.classList.contains("on");
    b.classList.toggle("on", v); b.setAttribute("aria-checked", String(v));
    onChange(v);
  });
  return b;
}

/** Pop-up button picker (SwiftUI Picker, menu style). */
export function picker<T>(options: Option<T>[], value: T, onChange: (v: T) => void, o: { width?: number; disabled?: boolean; label?: string } = {}): HTMLElement {
  const cur = () => options.find((x) => x.value === value);
  const text = h("span", { class: "pv", text: cur()?.title ?? String(value ?? "") });
  const b = h("button", { class: "picker" }, text, icon("chevron.up.chevron.down", 9, 2)) as HTMLButtonElement;
  if (o.width) b.style.width = o.width + "px";
  b.disabled = !!o.disabled;
  b.addEventListener("click", () => {
    if (b.disabled) return;
    const items: MenuItem[] = options.map((x) => ({ title: x.title, checked: x.value === value, disabled: x.disabled, symbol: x.symbol, action: () => { value = x.value; text.textContent = x.title; onChange(x.value); } }));
    showMenu(items, b, { minWidth: b.getBoundingClientRect().width });
  });
  b.addEventListener("keydown", (e) => {
    if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
    e.preventDefault();
    const i = options.findIndex((x) => x.value === value), j = Math.min(options.length - 1, Math.max(0, i + (e.key === "ArrowDown" ? 1 : -1)));
    if (j !== i && !options[j].disabled) { value = options[j].value; text.textContent = options[j].title; onChange(value); }
  });
  (b as any).setValue = (v: T) => { value = v; text.textContent = cur()?.title ?? String(v ?? ""); };
  if (!o.label) return b;
  return h("label", { class: "field-row" }, h("span", { class: "fl", text: o.label }), b);
}

/** Segmented control (Picker .segmented). */
export function segmented<T>(options: Option<T>[], value: T, onChange: (v: T) => void, width?: number): HTMLElement {
  const el = h("div", { class: "segmented" });
  if (width) el.style.width = width + "px";
  const render = () => {
    clear(el);
    for (const x of options) {
      const b = h("button", { class: "seg" + (x.value === value ? " sel" : ""), text: x.title });
      b.addEventListener("click", () => { value = x.value; render(); onChange(x.value); });
      el.append(b);
    }
  };
  render();
  return el;
}

/** Stepper with its label (SwiftUI Stepper: label, then the up/down arrows). */
export function stepper(label: (v: number) => string, value: number, min: number, max: number, onChange: (v: number) => void, o: { disabled?: boolean; step?: number } = {}): HTMLElement {
  const text = h("span", { class: "stl", text: label(value) });
  const up = h("button", { class: "stb", "aria-label": "Increment" }, icon("chevron.up", 8, 2.4)) as HTMLButtonElement;
  const down = h("button", { class: "stb", "aria-label": "Decrement" }, icon("chevron.down", 8, 2.4)) as HTMLButtonElement;
  const el = h("div", { class: "stepper" + (o.disabled ? " disabled" : "") }, text, h("span", { class: "stbs" }, up, down));
  const step = o.step ?? 1;
  const set = (v: number) => { v = Math.min(max, Math.max(min, v)); if (v === value) return; value = v; text.textContent = label(v); onChange(v); };
  up.addEventListener("click", () => { if (!o.disabled) set(value + step); });
  down.addEventListener("click", () => { if (!o.disabled) set(value - step); });
  up.disabled = down.disabled = !!o.disabled;
  (el as any).setLabel = () => { text.textContent = label(value); };
  return el;
}

/** Dark text field (.darkField()). */
export function textField(placeholder: string, value: string, onInput: (v: string) => void, o: { width?: number; onSubmit?: (v: string) => void; mono?: boolean; onBlur?: (v: string) => void } = {}): HTMLInputElement {
  const i = h("input", { class: "darkfield" + (o.mono ? " mono" : ""), placeholder, spellcheck: false }) as HTMLInputElement;
  i.value = value;
  if (o.width) i.style.width = o.width + "px";
  i.addEventListener("input", () => onInput(i.value));
  i.addEventListener("keydown", (e) => { if (e.key === "Enter" && o.onSubmit) { e.preventDefault(); e.stopPropagation(); o.onSubmit(i.value); } });
  if (o.onBlur) i.addEventListener("blur", () => o.onBlur!(i.value));
  return i;
}

/** Number field (TextField(value:format:.number)): keeps the last valid number; invalid text turns red. */
export function numberField(value: number, onChange: (v: number) => void, o: { width?: number; min?: number; positive?: boolean; integer?: boolean } = {}): HTMLInputElement {
  const i = h("input", { class: "darkfield num", spellcheck: false, inputmode: "decimal" }) as HTMLInputElement;
  i.value = fmtNumber(value);
  i.style.width = (o.width ?? 80) + "px";
  const parse = () => {
    const t = i.value.trim().replace(",", ".");
    const v = Number(t);
    const ok = t !== "" && Number.isFinite(v) && (o.positive ? v > 0 : true) && (o.min === undefined || v >= o.min) && (!o.integer || Number.isInteger(v));
    i.classList.toggle("invalid", !ok);
    return ok ? v : null;
  };
  i.addEventListener("input", () => { const v = parse(); if (v !== null) onChange(v); });
  i.addEventListener("blur", () => { if (parse() === null) { i.value = fmtNumber(value); i.classList.remove("invalid"); } else value = parse()!; });
  return i;
}
export function fmtNumber(v: number): string {
  if (!Number.isFinite(v)) return "";
  const r = Math.round(v * 1e6) / 1e6;
  return String(r);
}

export function slider(min: number, max: number, step: number, value: number, onChange: (v: number) => void, width = 200): HTMLInputElement {
  const s = h("input", { type: "range", class: "slider", min: String(min), max: String(max), step: String(step) }) as HTMLInputElement;
  s.value = String(value);
  s.style.width = width + "px";
  s.addEventListener("input", () => onChange(Number(s.value)));
  return s;
}

/** Vertical radio group (Picker .radioGroup). */
export function radioGroup<T>(options: Option<T>[], value: T, onChange: (v: T) => void): HTMLElement {
  const el = h("div", { class: "radios", role: "radiogroup" });
  const render = () => {
    clear(el);
    for (const x of options) {
      const b = h("button", { class: "radio" + (x.value === value ? " on" : ""), role: "radio", "aria-checked": String(x.value === value) }, h("span", { class: "dot" }), h("span", { text: x.title }));
      b.addEventListener("click", () => { value = x.value; render(); onChange(x.value); });
      el.append(b);
    }
  };
  render();
  return el;
}

/** PrefSection: upper-case caption over a rounded field-coloured box. */
export function section(title: string, ...children: Child[]): HTMLElement {
  return h("div", { class: "psec" }, h("div", { class: "psec-t", text: title.toUpperCase() }), h("div", { class: "psec-b" }, ...children));
}
export function row(...children: Child[]): HTMLElement { return h("div", { class: "drow" }, ...children); }
export function col(...children: Child[]): HTMLElement { return h("div", { class: "dcol" }, ...children); }
export function note(text: string, cls = ""): HTMLElement { return h("div", { class: "dnote" + (cls ? " " + cls : ""), text }); }
export function label(text: string, o: { dim?: boolean; bold?: boolean; width?: number; mono?: boolean } = {}): HTMLElement {
  const e = h("span", { class: "dlabel" + (o.dim ? " dim" : "") + (o.bold ? " bold" : "") + (o.mono ? " mono" : ""), text });
  if (o.width) { e.style.width = o.width + "px"; e.style.flex = "none"; }
  return e;
}
export function divider(): HTMLElement { return h("div", { class: "hsep ddiv" }); }
export function spacer(): HTMLElement { return h("span", { class: "spacer" }); }

// ---- alerts (NSAlert) ----
export function alertDialog(message: string, informative: string, buttons: string[] = ["OK"]): Promise<number> {
  return new Promise((resolve) => {
    let done = false;
    const finish = (i: number) => { if (!done) { done = true; handle.close(); resolve(i); } };
    const content = h("div", { class: "alert" }, h("img", { src: "assets/app-icon.png", alt: "", class: "alert-icon" }), h("div", {}, h("div", { class: "alert-m", text: message }), informative ? h("div", { class: "alert-i", text: informative }) : null));
    const btns = buttons.map((t, i) => flatButton(t, () => finish(i), { prominent: i === 0 }));
    const handle = sheet({ title: "Oanarina Archi Tool", content, width: 420, footerButtons: btns.slice(1).reverse().concat(btns.slice(0, 1)), onCancel: null, onOK: null });
    handle.el.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); finish(0); } else if (e.key === "Escape") { e.preventDefault(); finish(buttons.length > 1 ? 1 : 0); } }, true);
    requestAnimationFrame(() => btns[0].focus());
  });
}

export function promptDialog(message: string, informative: string, value: string, okTitle = "Save"): Promise<string | null> {
  return new Promise((resolve) => {
    let result: string | null = null;
    const f = textField("", value, (v) => { result = v; }, { width: 280 });
    result = value;
    const content = h("div", { class: "alert" }, h("img", { src: "assets/app-icon.png", alt: "", class: "alert-icon" }),
      h("div", {}, h("div", { class: "alert-m", text: message }), informative ? h("div", { class: "alert-i", text: informative }) : null, f));
    let answered = false;
    sheet({ title: "Oanarina Archi Tool", content, width: 420, okTitle, onOK: () => { answered = true; resolve(result); }, onCancel: () => { answered = true; resolve(null); } });
    void answered;
    requestAnimationFrame(() => { f.focus(); f.select(); });
  });
}

/** Browser download of a text file (fixture / web mode, where there is no native save dialog). */
export function downloadText(name: string, text: string) {
  const a = h("a", { href: URL.createObjectURL(new Blob([text], { type: "application/json" })), download: name }) as HTMLAnchorElement;
  document.body.append(a); a.click(); a.remove();
}
/** Browser file picker (web mode). */
export function pickTextFile(accept = ".json"): Promise<string | null> {
  return new Promise((resolve) => {
    const i = h("input", { type: "file", accept }) as HTMLInputElement;
    i.addEventListener("change", async () => { const f = i.files?.[0]; resolve(f ? await f.text() : null); });
    i.click();
  });
}
