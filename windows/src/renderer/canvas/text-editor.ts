// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Double-click text editing (CanvasView.editObject, AppRound12TextEditor.swift InPlaceTextEditor, ANN-003): text opens an
// editor over the text on the canvas at its drawn size with Bold / Italic / Underline, font, height, colour and ByLayer,
// OK and Cancel (Enter commits single-line text, Ctrl+Enter multi-line, Esc cancels, clicking elsewhere keeps the edit);
// leaders and dimensions open the "Edit Text" alert. Commits are one "Edit Text" undo step (text.edit).
import type { App } from "../app";
import { h } from "../dom";
import { help } from "../ui/menu";
import { cssFont } from "./drawitems";
import { sheet } from "../dialogs/ui";

/** Windows font families offered in the font picker (the Mac lists NSFontManager.availableFontFamilies). */
export const FONT_FAMILIES = ["Arial", "Bahnschrift", "Calibri", "Cambria", "Candara", "Consolas", "Constantia", "Corbel", "Courier New", "Franklin Gothic Medium",
  "Georgia", "Gill Sans MT", "Lucida Console", "Palatino Linotype", "Segoe UI", "Tahoma", "Times New Roman", "Trebuchet MS", "Verdana"];

function hexOf(color: string | undefined): string | null {
  if (!color) return null;
  const m = /^RGB:(\d+),(\d+),(\d+)$/i.exec(color.trim()) ?? /^(\d+),(\d+),(\d+)$/.exec(color.trim());
  if (m) return "#" + [m[1], m[2], m[3]].map((v) => Math.max(0, Math.min(255, Number(v))).toString(16).padStart(2, "0")).join("");
  if (/^#[0-9a-f]{6}$/i.test(color)) return color;
  return null;
}

export interface TextEditRequest {
  id: number; content: string; singleLine: boolean; styleFont: string; color: string;
  format: { font?: string; bold?: boolean; italic?: boolean; underline?: boolean };
  text: { position: [number, number]; height: number; rotation: number; halign: string; width: number };
}

/** The in-place editor; `at` maps a world point to canvas coordinates, `scale` is screen px per drawing unit. */
export class InPlaceTextEditor {
  static current: InPlaceTextEditor | null = null;
  el: HTMLElement;
  area: HTMLTextAreaElement;
  private finished = false;
  private state: { content: string; height: number; font: string | null; bold: boolean; italic: boolean; underline: boolean; color: string };
  private original: string;

  constructor(private app: App, private req: TextEditRequest, host: HTMLElement, at: (p: [number, number]) => [number, number], private scale: number, private done: () => void) {
    InPlaceTextEditor.current?.commit();
    InPlaceTextEditor.current = this;
    this.state = { content: req.content, height: req.text.height, font: req.format.font ?? null, bold: !!req.format.bold, italic: !!req.format.italic, underline: !!req.format.underline, color: req.color || "ByLayer" };
    this.original = JSON.stringify(this.state);
    this.el = h("div", { class: "text-editor", role: "dialog", "aria-label": "In-place text editor" });
    const bar = h("div", { class: "te-bar" });
    const fmtBtn = (label: string, key: "bold" | "italic" | "underline", tip: string, style: string) => {
      const b = h("button", { class: "te-btn" + (this.state[key] ? " on" : ""), text: label, style: { cssText: style } }) as HTMLButtonElement;
      help(b, tip);
      b.addEventListener("mousedown", (e) => e.preventDefault());
      b.addEventListener("click", () => { this.state[key] = !this.state[key]; b.classList.toggle("on", this.state[key]); this.applyFormatting(); this.area.focus(); });
      return b;
    };
    const font = h("select", { class: "te-font" }) as HTMLSelectElement;
    font.append(h("option", { value: "", text: `Style font (${req.styleFont})` }));
    for (const f of FONT_FAMILIES) font.append(h("option", { value: f, text: f }));
    if (this.state.font && !FONT_FAMILIES.includes(this.state.font)) font.append(h("option", { value: this.state.font, text: this.state.font }));
    font.value = this.state.font ?? "";
    help(font, "Font");
    font.addEventListener("change", () => { this.state.font = font.value || null; this.applyFormatting(); });
    const height = h("input", { class: "te-height", value: fmtNum(this.state.height), "aria-label": "Text height" }) as HTMLInputElement;
    help(height, "Text height (drawing units)");
    const setHeight = () => {
      const v = Number(height.value.replace(",", "."));
      if (v > 0 && isFinite(v)) { this.state.height = v; this.applyFormatting(); } else height.value = fmtNum(this.state.height);
    };
    height.addEventListener("change", setHeight);
    const color = h("input", { type: "color", class: "te-color", value: hexOf(this.state.color) ?? "#ffffff" }) as HTMLInputElement;
    help(color, "Text colour");
    const byLayer = h("input", { type: "checkbox", checked: this.state.color.toUpperCase() === "BYLAYER" }) as HTMLInputElement;
    color.addEventListener("input", () => {
      this.state.color = color.value.toUpperCase();
      byLayer.checked = false; this.applyFormatting();
    });
    byLayer.addEventListener("change", () => { this.state.color = byLayer.checked ? "ByLayer" : (req.color && req.color.toUpperCase() !== "BYLAYER" ? req.color : "#FFFFFF"); this.applyFormatting(); });
    const ok = h("button", { class: "te-ok", text: "OK" }); help(ok, "Apply (Ctrl+Enter)");
    const cancel = h("button", { class: "te-cancel", text: "Cancel" }); help(cancel, "Discard (Esc)");
    ok.addEventListener("click", () => this.commit());
    cancel.addEventListener("click", () => this.cancel());
    bar.append(fmtBtn("B", "bold", "Bold", "font-weight:700"), fmtBtn("I", "italic", "Italic", "font-style:italic"), fmtBtn("U", "underline", "Underline", "text-decoration:underline"),
      font, height, color, h("label", { class: "te-bylayer" }, byLayer, h("span", { text: "ByLayer" })), ok, cancel);
    this.area = h("textarea", { class: "te-text", spellcheck: false, "aria-label": "Text" }) as HTMLTextAreaElement;
    this.area.value = req.content;
    this.el.append(bar, this.area);
    this.el.addEventListener("keydown", (e) => {
      e.stopPropagation();
      if (e.key === "Escape") { e.preventDefault(); this.cancel(); }
      else if (e.key === "Enter" && e.target === this.area && (req.singleLine || e.ctrlKey || e.metaKey)) { e.preventDefault(); this.commit(); }
    });
    this.el.addEventListener("keyup", (e) => e.stopPropagation());
    this.el.addEventListener("mousedown", (e) => e.stopPropagation());
    this.el.addEventListener("focusout", () => setTimeout(() => { if (!this.finished && !this.el.contains(document.activeElement)) this.commit(); }, 0));
    host.append(this.el);
    this.layout(at(req.text.position), host.getBoundingClientRect());
    this.applyFormatting();
    this.area.focus();
    this.area.select();
  }

  get pointSize() { return Math.min(96, Math.max(9, (this.state.height * this.scale) / 0.717)); }

  private layout(p: [number, number], bounds: DOMRect) {
    const fs = this.pointSize, lineH = fs * 1.3;
    const lines = Math.max(1, this.state.content.split("\n").length);
    const ctx = document.createElement("canvas").getContext("2d")!;
    ctx.font = `${fs}px ${cssFont(this.state.font ?? this.req.styleFont)}`;
    const natural = Math.max(...this.state.content.split("\n").map((l) => ctx.measureText(l).width));
    let w = this.req.text.width > 0 ? this.req.text.width * this.scale : natural + 40;
    w = Math.min(Math.max(w, 540), Math.max(540, bounds.width - 20));
    const hh = lines * lineH + 14 + 30;
    let x = p[0] - 6;
    if (this.req.text.halign === "center" || this.req.text.halign === "middle") x -= w / 2; else if (this.req.text.halign === "right") x -= w;
    // Baseline of the first line on the text's insertion point.
    let y = p[1] - 30 - lineH * 0.75 - 7;
    x = Math.min(Math.max(4, x), bounds.width - w - 4);
    y = Math.min(Math.max(4, y), bounds.height - hh - 4);
    Object.assign(this.el.style, { left: x + "px", top: y + "px", width: w + "px", height: hh + "px" });
  }

  private applyFormatting() {
    const s = this.area.style;
    s.fontFamily = cssFont(this.state.font ?? this.req.styleFont);
    s.fontSize = this.pointSize + "px";
    s.fontWeight = this.state.bold ? "700" : "400";
    s.fontStyle = this.state.italic ? "italic" : "normal";
    s.textDecoration = this.state.underline ? "underline" : "none";
    const hex = hexOf(this.state.color);
    s.color = hex ?? "var(--text)";
    s.caretColor = hex ?? "var(--text)";
  }

  async commit() {
    if (this.finished) return;
    this.finished = true;
    this.state.content = this.area.value;
    const changed = JSON.stringify(this.state) !== this.original;
    this.close();
    if (!changed) return;
    if (!this.state.content.trim()) { this.app.print("Error: text is empty"); return; }
    await this.app.tryCall("text.edit", { id: this.req.id, content: this.state.content, height: this.state.height, font: this.state.font ?? "",
      bold: this.state.bold, italic: this.state.italic, underline: this.state.underline, color: this.state.color });
    await this.app.refresh(["drawing", "properties", "history"]);
  }
  cancel() { this.finished = true; this.close(); }
  private close() {
    this.el.remove();
    if (InPlaceTextEditor.current === this) InPlaceTextEditor.current = null;
    this.done();
  }
  /** Test hook: types into the editor. */
  setText(s: string) { this.area.value = s; }
}

function fmtNum(v: number) { const s = v.toFixed(4); return s.includes(".") ? s.replace(/\.?0+$/, "") : s; }

/** The "Edit Text" alert for leaders and dimensions (CanvasView.editObject, an NSAlert with a text field / text view).
 *  Resolves with the new text or null. */
export function editTextAlert(message: string, value: string, multiline: boolean): Promise<string | null> {
  return new Promise((resolve) => {
    const input = (multiline ? h("textarea", { class: "darkfield edit-text-area", spellcheck: false, style: { width: "320px", height: "90px" } })
      : h("input", { class: "darkfield", spellcheck: false, style: { width: "320px" } })) as HTMLInputElement | HTMLTextAreaElement;
    input.value = value;
    let answered = false;
    const content = h("div", { class: "alert" }, h("img", { src: "assets/app-icon.png", alt: "", class: "alert-icon" }),
      h("div", {}, h("div", { class: "alert-m", text: "Edit Text" }), h("div", { class: "alert-i", text: message }), input));
    const handle = sheet({ title: "Oanarina Archi Tool", content, width: 440, okTitle: "OK",
      onOK: () => { if (!answered) { answered = true; resolve(input.value); } }, onCancel: () => { if (!answered) { answered = true; resolve(null); } } });
    handle.el.classList.add("edit-text-alert");
    if (multiline) input.addEventListener("keydown", (ev) => { const e = ev as KeyboardEvent; if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) { e.preventDefault(); handle.ok?.click(); } });
    requestAnimationFrame(() => { input.focus(); (input as HTMLInputElement).select?.(); });
  });
}
