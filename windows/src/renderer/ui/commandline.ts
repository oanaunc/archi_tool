// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// AutoCAD-style command line (CommandLineView.swift): history, prompt with keyword chips, input with autocomplete,
// Enter/Space submit, Esc cancel, Up/Down history, Tab completion.
import type { App } from "../app";
import { h, clear } from "../dom";
import { icon } from "../icons";
import { help } from "./menu";

/** Command line appearance (CommandLineAppearance, CMDLINEOPTIONS): text size, history lines, background opacity. */
export const cmdAppearance = { font: 11, lines: 4, opacity: 0.55 };
const rowHeight = () => Math.round(Math.min(Math.max(cmdAppearance.font, 8), 20) * 1.36);

export class CommandLine {
  el: HTMLElement;
  input: HTMLInputElement;
  private lines: HTMLElement;
  private historyBox: HTMLElement;
  private prompt: HTMLElement;
  private row: HTMLElement;
  private sugg: HTMLElement | null = null;
  private suggIndex = 0;
  private suggNavigated = false;
  private suggDismissed = false;
  private histIndex: number | null = null;
  private expanded = false;
  private rendered = 0;

  constructor(private app: App) {
    this.lines = h("div", { class: "lines" });
    const exp = h("button", { class: "iconbtn expand" }, icon("chevron.up", 11, 2));
    help(exp, "Expand command history");
    exp.addEventListener("click", () => { this.expanded = !this.expanded; exp.replaceChildren(icon(this.expanded ? "chevron.down" : "chevron.up", 11, 2)); this.layout(); });
    this.historyBox = h("div", { class: "cmd-history" }, this.lines, exp);
    this.prompt = h("div", { class: "prompt" });
    this.input = h("input", { type: "text", spellcheck: false, autocomplete: "off", "aria-label": "Command line" }) as HTMLInputElement;
    this.row = h("div", { class: "cmd-input" }, h("span", { class: "chev" }, icon("chevron.right.2", 11, 2.4)), this.prompt, this.input);
    this.el = h("div", { class: "cmdline" }, this.historyBox, h("div", { class: "hsep" }), this.row);
    this.layout();
    this.renderPrompt(); this.renderLog(true);
    app.on("log", () => this.renderLog());
    app.on("prompt", () => this.renderPrompt());
    this.input.addEventListener("input", () => this.onInput());
    this.input.addEventListener("keydown", (e) => this.onKey(e));
    this.input.addEventListener("blur", () => setTimeout(() => this.hideSuggestions(), 150));
  }

  private layout() {
    const row = rowHeight(), n = Math.min(Math.max(cmdAppearance.lines, 1), 40);
    this.el.style.setProperty("--cl-font", `${cmdAppearance.font}px`);
    this.el.style.setProperty("--cl-row", `${row}px`);
    this.el.style.setProperty("--cl-opacity", String(cmdAppearance.opacity));
    this.historyBox.style.height = (this.expanded ? Math.max(240, row * n + 6) : row * n + 6) + "px";
    this.lines.scrollTop = 1e9;
  }
  /** Applies cmdAppearance (CMDLINEOPTIONS). */
  relayout() { this.layout(); }

  private cls(line: string) {
    if (line.startsWith("Command: ")) return "ln cmd";
    const l = line.toLowerCase();
    if (l.startsWith("unknown command") || l.startsWith("invalid") || l.startsWith("error") || l.includes("cannot")) return "ln err";
    if (line.endsWith(":") || line.includes("]:") || line.includes(">:") || line.startsWith("*")) return "ln dim";
    return "ln";
  }
  private renderLog(all = false) {
    const log = this.app.log;
    if (all || this.rendered > log.length) { clear(this.lines); this.rendered = 0; }
    const start = Math.max(this.rendered, log.length - 200);
    for (let i = start; i < log.length; i++) this.lines.append(h("div", { class: this.cls(log[i]), text: log[i] }));
    this.rendered = log.length;
    while (this.lines.childElementCount > 200) this.lines.firstElementChild!.remove();
    this.lines.scrollTop = 1e9;
  }
  private renderPrompt() {
    const p = this.app.prompt;
    clear(this.prompt);
    this.row.classList.toggle("busy", p.active);
    if (p.active) {
      this.prompt.append(h("span", { class: "msg", text: p.label ?? p.message.replace(/\s*\[[^\]]*\]/, "").replace(/\s*<[^>]*>/, "").replace(/:\s*$/, "") }));
      if (p.keywords.length) {
        this.prompt.append(h("span", { text: "[" }));
        for (const k of p.keywords) {
          const b = h("button", { class: "kw", text: k }); help(b, `Choose ${k}`);
          b.addEventListener("mousedown", (e) => e.preventDefault());
          b.addEventListener("click", () => this.app.keyword(k));
          this.prompt.append(b);
        }
        this.prompt.append(h("span", { text: "]" }));
      }
      if (p.defaultValue) this.prompt.append(h("span", { text: `<${p.defaultValue}>` }));
      this.prompt.append(h("span", { text: ":" }));
      this.input.placeholder = "";
      if (!this.row.querySelector(".esc")) {
        const esc = h("button", { class: "flatbtn esc", text: "Esc", style: { fontSize: "10px", padding: "1px 6px" } });
        help(esc, "Cancel the current command (Esc)"); esc.addEventListener("click", () => this.app.cancel());
        this.row.append(esc);
      }
    } else {
      this.prompt.append(h("span", { text: "Command:" }));
      this.input.placeholder = "Type a command";
      this.row.querySelector(".esc")?.remove();
    }
  }

  // ---- autocomplete ----
  private suggestions() {
    const t = this.input.value.trim();
    if (this.app.prompt.active || this.suggDismissed || !t || t.includes(" ") || !/^[a-z]/i.test(t)) return [];
    return this.app.complete(t, 9);
  }
  private onInput() {
    this.suggIndex = 0; this.suggNavigated = false;
    if (!this.input.value) { this.suggDismissed = false; this.histIndex = null; }
    const v = this.input.value;
    if (v.endsWith(" ") && this.spaceSubmits(v.slice(0, -1))) { this.input.value = ""; this.submit(v.slice(0, -1)); return; }
    this.app.commandInput = this.input.value; this.app.emit("live");
    this.showSuggestions();
  }
  private spaceSubmits(text: string) {
    if ((text.match(/"/g) ?? []).length % 2 === 1) return false;
    const k = this.app.prompt.kinds;
    if (this.app.prompt.active && k.includes("string") && !k.includes("point")) return false;
    return true;
  }
  private showSuggestions() {
    const s = this.suggestions();
    this.hideSuggestions();
    if (!s.length) return;
    this.sugg = h("div", { class: "suggest" });
    s.forEach((x, i) => {
      const row = h("div", { class: "s" + (i === this.suggIndex ? " sel" : "") }, icon("terminal", 10), h("span", { class: "n", text: x.name }),
        x.name !== x.command.name ? h("span", { class: "to", text: `→ ${x.command.name}` }) : null, h("span", { class: "sum", text: x.command.summary }));
      row.addEventListener("mousedown", (e) => { e.preventDefault(); this.input.value = ""; this.submit(x.command.name); });
      this.sugg!.append(row);
    });
    this.sugg.style.bottom = "34px";
    this.el.append(this.sugg);
  }
  private hideSuggestions() { this.sugg?.remove(); this.sugg = null; }

  private submit(text: string) {
    const s = this.suggestions();
    let line = text;
    if (this.suggNavigated && s[this.suggIndex]) line = s[this.suggIndex].command.name;
    this.input.value = ""; this.app.commandInput = ""; this.histIndex = null; this.suggDismissed = false;
    this.hideSuggestions();
    this.app.submitLine(line);
  }
  private onKey(e: KeyboardEvent) {
    e.stopPropagation();
    const s = this.suggestions();
    switch (e.key) {
      case "Enter": e.preventDefault(); this.submit(this.input.value); break;
      case "Escape":
        e.preventDefault();
        if (s.length && this.sugg) { this.suggDismissed = true; this.hideSuggestions(); break; }
        this.input.value = ""; this.app.commandInput = ""; this.app.cancel(); this.app.canvas?.focus(); break;
      case "ArrowUp":
        e.preventDefault();
        if (s.length && this.sugg) { this.suggIndex = (this.suggIndex - 1 + s.length) % s.length; this.suggNavigated = true; this.showSuggestions(); break; }
        if (this.app.inputHistory.length) { const i = Math.max(0, (this.histIndex ?? this.app.inputHistory.length) - 1); this.histIndex = i; this.input.value = this.app.inputHistory[i]; this.suggDismissed = true; }
        break;
      case "ArrowDown":
        e.preventDefault();
        if (s.length && this.sugg) { this.suggIndex = (this.suggIndex + 1) % s.length; this.suggNavigated = true; this.showSuggestions(); break; }
        if (this.histIndex !== null) {
          if (this.histIndex + 1 < this.app.inputHistory.length) { this.histIndex++; this.input.value = this.app.inputHistory[this.histIndex]; this.suggDismissed = true; }
          else { this.histIndex = null; this.input.value = ""; }
        }
        break;
      case "Tab": e.preventDefault(); if (s[this.suggIndex]) { this.input.value = s[this.suggIndex].name; this.suggDismissed = true; this.hideSuggestions(); } break;
      case "Backspace": case "Delete":
        if (!this.input.value && this.app.isIdle && this.app.selection.ids.length) { e.preventDefault(); this.app.runCommand("ERASE"); }
        break;
      default:
        if ((e.ctrlKey || e.metaKey) && !e.altKey && ["z", "y", "s", "o", "n", "p", "k", "0"].includes(e.key.toLowerCase())) document.dispatchEvent(new KeyboardEvent("keydown", e));
    }
  }
  /** Types a key from the canvas into the command line (just start typing — the Mac behaviour). */
  typeKey(ch: string) { this.input.focus(); this.input.value += ch; this.onInput(); }
  focus() { this.input.focus(); }
}
