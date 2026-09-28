// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Contextual ribbon tab (ArchiApp/AppNavigationViews.swift ContextualRibbonStrip, APP-015): while the selection is all of
// one kind, an accent-coloured strip under the ribbon shows its tab — "MODIFY WALL", "TEXT EDITOR", "HATCH EDITOR",
// "DIMENSION", "BLOCK REFERENCE", "POLYLINE", "TABLE CELL", "MODIFY ROOM", "MODIFY DOOR" / "MODIFY WINDOW" or
// "MODIFY <kind>" — with that kind's commands and Move, Copy, Rotate, Mirror, Match Props, Select Similar. The engine
// decides the tab (ribbon.context = the Mac's ContextualRibbon.tab) and leaves out commands that are not registered.
import type { App } from "../app";
import { h, clear } from "../dom";
import { icon } from "../icons";
import { help } from "../ui/menu";

export interface ContextItem { title: string; symbol: string; command: string; names?: string[]; help?: string }
export interface ContextTab { title: string; category: string; items: ContextItem[] }

export class ContextStrip {
  el: HTMLElement;
  tab: ContextTab | null = null;
  private seq = 0;
  private timer: ReturnType<typeof setTimeout> | null = null;

  constructor(private app: App) {
    this.el = h("div", { class: "ctx-strip", role: "toolbar" });
    this.el.style.display = "none";
    app.on(["selection", "doc"], () => this.schedule());
  }

  private schedule() {
    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => { this.timer = null; void this.refresh(); }, 25);
  }

  async refresh() {
    const seq = ++this.seq;
    const r = this.app.selection.ids.length ? await this.app.tryCall("ribbon.context", {}) : null;
    if (seq !== this.seq) return;
    this.render((r?.tab as ContextTab | null) ?? null);
  }

  render(tab: ContextTab | null) {
    this.tab = tab;
    clear(this.el);
    if (!tab || !tab.items?.length) { this.el.style.display = "none"; this.el.removeAttribute("aria-label"); return; }
    this.el.style.display = "";
    this.el.setAttribute("aria-label", tab.title);
    this.el.append(h("span", { class: "ctx-title", text: tab.title.toUpperCase() }));
    for (const it of tab.items) {
      const b = h("button", { class: "ctx-btn", "data-command": it.command }, icon(it.symbol || "terminal", 12, 1.7), h("span", { text: it.title }));
      help(b, it.help ?? this.helpText(it.command));
      b.addEventListener("click", () => void this.app.runCommand(it.command));
      this.el.append(b);
    }
  }

  private helpText(name: string) {
    const d = this.app.lookup(name);
    return d ? `${d.name} — ${d.summary}` : name;
  }
}
