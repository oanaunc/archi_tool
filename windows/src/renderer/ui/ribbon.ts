// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Ribbon (RibbonView.swift): quick access toolbar, tabs, groups with large buttons, small-button columns, catalogue
// menus and drop-downs, generated from docs/windows-parity.json (or the fallback extracted from the Mac sources).
import type { App } from "../app";
import { h, clear } from "../dom";
import { icon } from "../icons";
import { showMenu, help, MenuItem } from "./menu";
import ui from "../data/ui.generated.json";
import * as dd from "./dropdowns";
import { prefs } from "../prefs";
import { customRibbonPanels, isHiddenRibbonPanel, dynamicMenu, openSettings } from "../dialogs";
import { resolveEntry, runEntry, uiKnown } from "./shell-commands";
import { t as tr } from "../workspace/l10n";

export interface RItem {
  title: string; symbol?: string; command?: string; args?: string; names?: string[]; size?: "large" | "small"; rows?: number;
  kind?: "command" | "action" | "menu" | "dropdown" | "agentStatus"; dropdown?: string; width?: number; help?: string; label?: string; note?: string;
  sections?: { name: string; items: RItem[] }[]; inline?: boolean;
}
export interface RGroup { name: string; items: RItem[] }
export interface RTab { tab: string; groups: RGroup[] }
export const RIBBON = (ui as any).ribbon as RTab[];
export const QUICK_ACCESS = ["NEW", "OPEN", "SAVE", "UNDO", "REDO", "PLOT"];
const QA_SYMBOL: Record<string, string> = { NEW: "doc.badge.plus", OPEN: "folder", SAVE: "square.and.arrow.down", SAVEAS: "square.and.arrow.down.on.square", UNDO: "arrow.uturn.backward",
  REDO: "arrow.uturn.forward", PLOT: "printer", PREVIEW: "eye", PUBLISH: "doc.on.doc", MATCHPROP: "paintbrush.pointed", QSELECTDIALOG: "line.3.horizontal.decrease.circle",
  LAYER: "square.3.layers.3d", RENDER: "camera.aperture", OPTIONS: "gearshape" };

/** Ribbon title of a command (CommandCatalog.title): the first catalogue item that runs it. */
export function ribbonTitle(name: string): string | undefined {
  const n = name.toUpperCase();
  const walk = (items: any[]): string | undefined => { for (const it of items ?? []) { if (it?.command && String(it.command).toUpperCase() === n && it.title && !/\{/.test(it.title)) return it.title; for (const s of it?.sections ?? []) { const r = walk(s.items); if (r) return r; } } return undefined; };
  for (const t of RIBBON) for (const g of t.groups) { const r = walk(g.items); if (r) return r; }
  return undefined;
}
export function commandLine(it: RItem) { return it.command ? (it.args ? `${it.command} ${it.args}` : it.command) : ""; }
/** The command a ribbon entry runs (engine command, shell command or "@" action; ui/shell-commands.ts), null = disabled. */
export function resolveCommand(app: App, it: RItem): string | null { return resolveEntry(app, it); }

export class Ribbon {
  el: HTMLElement;
  private body: HTMLElement;
  private tabsEl: HTMLElement;
  private buttons: { el: HTMLElement; it: RItem }[] = [];

  constructor(private app: App) {
    this.tabsEl = h("div", { class: "ribbon-tabs" });
    this.body = h("div", { class: "ribbon-body" });
    this.el = h("div", { class: "ribbon" }, this.tabsEl, this.body);
    this.renderTabs(); this.renderBody();
    app.on("ui", () => { this.renderTabs(); if (!app.ribbonCollapsed) this.renderBody(); this.body.style.display = app.ribbonCollapsed ? "none" : ""; });
    app.on(["prompt", "selection"], () => this.updateStates());
    app.on("doc", () => this.renderTabs());
    this.body.addEventListener("wheel", (e) => { if (Math.abs(e.deltaY) > Math.abs(e.deltaX)) { this.body.scrollLeft += e.deltaY; e.preventDefault(); } }, { passive: false });
  }

  private renderTabs() {
    const app = this.app;
    clear(this.tabsEl);
    const logo = h("button", { class: "app-btn" }, h("img", { src: "assets/app-icon.png", alt: "" }));
    help(logo, "About Oanarina Archi Tool");
    logo.addEventListener("click", () => void runEntry(app, { command: "ABOUT" }));
    this.tabsEl.append(logo);
    for (const n of prefs.quickAccess) {
      const def = app.lookup(n);
      const b = h("button", { class: "iconbtn" }, icon(QA_SYMBOL[n] ?? "terminal", 14, 1.7));
      help(b, def ? `${def.name} — ${def.summary}` : n);
      b.addEventListener("click", () => n === "UNDO" ? app.undo() : n === "REDO" ? app.redo() : n === "NEW" ? app.engine.native ? app.engine.native.newWindow({ kind: "start" }) : app.newDocument() : n === "OPEN" ? app.open() : n === "SAVE" ? app.save() : app.runCommand(n));
      this.tabsEl.append(b);
    }
    const more = h("button", { class: "iconbtn small-chevron" }, icon("chevron.down", 9, 2));
    help(more, "Customize the quick access toolbar");
    more.addEventListener("click", () => showMenu(["NEW", "OPEN", "SAVE", "SAVEAS", "UNDO", "REDO", "PLOT", "PREVIEW", "PUBLISH", "MATCHPROP", "QSELECTDIALOG", "LAYER", "RENDER", "OPTIONS"]
      .map((n) => ({ title: n, checked: prefs.quickAccess.includes(n), action: () => { const q = prefs.quickAccess; const i = q.indexOf(n); if (i >= 0) q.splice(i, 1); else q.push(n); prefs.set("quickAccess", q); } }) as MenuItem)
      .concat([{ separator: true }, { title: "More Commands…", action: () => openSettings("Toolbar") }]), more));
    this.tabsEl.append(more, h("div", { class: "vsep", style: { height: "14px", alignSelf: "center", margin: "0 4px" } }));
    for (const t of RIBBON.filter((x) => !prefs.hiddenRibbonTabs.includes(x.tab) || x.tab === app.ribbonTab)) {
      const b = h("button", { class: "tab" + (t.tab === app.ribbonTab ? " sel" : ""), text: tr(t.tab) });
      b.addEventListener("click", () => { app.setUI("ribbonTab", t.tab); if (app.ribbonCollapsed) app.setUI("ribbonCollapsed", false); });
      this.tabsEl.append(b);
    }
    this.tabsEl.append(h("div", { class: "spacer" }));
    const right: [string, string, () => void, boolean?][] = [
      ["magnifyingglass", "Search commands (Ctrl+K)", () => document.dispatchEvent(new CustomEvent("archi:commandSearch"))],
      ["rectangle.dashed", "Clean screen (Ctrl+0)", () => app.action("@cleanScreen")],
      ["sidebar.right", app.showPanels ? "Hide panels" : "Show panels", () => app.setUI("showPanels", !app.showPanels), app.showPanels],
      [app.ribbonCollapsed ? "chevron.down" : "chevron.up", app.ribbonCollapsed ? "Expand the ribbon" : "Collapse the ribbon", () => app.setUI("ribbonCollapsed", !app.ribbonCollapsed)],
    ];
    for (const [sym, tip, act, active] of right) {
      const b = h("button", { class: "iconbtn" + (active ? " active" : "") }, icon(sym, 13, 1.8));
      help(b, tip); b.addEventListener("click", act); this.tabsEl.append(b);
    }
    (this.tabsEl.lastChild as HTMLElement).style.marginRight = "6px";
  }

  private renderBody() {
    clear(this.body);
    this.buttons = [];
    const tab = RIBBON.find((t) => t.tab === this.app.ribbonTab) ?? RIBBON[0];
    for (const g of tab.groups) if (!isHiddenRibbonPanel(g.name)) this.body.append(this.group(g));
    for (const g of customRibbonPanels(tab.tab, ribbonTitle)) this.body.append(this.group(g as RGroup));
    this.updateStates();
  }

  private group(g: RGroup): HTMLElement {
    const content = h("div", { class: "content" });
    const items = g.items;
    const hasDropdown = items.some((i) => i.kind === "dropdown");
    if (hasDropdown) {
      // Stacked layout: drop-down(s) with small buttons underneath (Layers, Properties, Level, Style, Visual Style).
      const stack = h("div", { class: "rstack" + (items.every((i) => i.kind === "dropdown") && items.length > 2 ? " tight" : "") });
      stack.style.paddingTop = items.length === 1 || g.name === "Style" || g.name === "Visual Style" ? "4px" : "0";
      let row: HTMLElement | null = null;
      for (const it of items) {
        if (it.kind === "dropdown") {
          if (it.label) stack.append(h("div", { class: "rnote", text: it.label }));
          stack.append(this.dropdown(it));
          if (it.dropdown === "dimstyle") stack.append(h("div", { class: "rnote", text: `Text height: ${this.app.sysvars.TEXTSIZE ?? "2.5"}` }));
          if (it.note) stack.append(h("div", { class: "rnote", text: it.note }));
          row = null;
        } else {
          if (!row) { row = h("div", { class: "rrow" }); stack.append(row); }
          row.append(this.button({ ...it, size: "small" }));
        }
      }
      content.append(stack);
    } else {
      let col: HTMLElement | null = null, rows = 3, n = 0;
      for (const it of items) {
        const small = (it.size ?? "large") === "small" && it.kind !== "menu" && it.kind !== "agentStatus";
        if (!small) { col = null; content.append(it.kind === "agentStatus" ? this.agentStatus() : this.button(it)); continue; }
        if (!col || it.rows !== undefined || n >= rows) {
          if (!col || it.rows !== undefined) rows = it.rows ?? 3;
          col = h("div", { class: "rcol" }); content.append(col); n = 0;
        }
        col.append(this.button(it)); n++;
      }
    }
    return h("div", { class: "rgroup" }, h("div", { class: "inner" }, content, h("div", { class: "label", text: tr(g.name) })), h("div", { class: "vsep" }));
  }

  private dropdown(it: RItem): HTMLElement {
    const w = it.width ?? 170;
    switch (it.dropdown) {
      case "layer": return dd.layerDropdown(this.app, w);
      case "level": return dd.levelDropdown(this.app, w);
      case "color": return dd.colorDropdown(this.app, w);
      case "linetype": return dd.linetypeDropdown(this.app, w);
      case "lineweight": return dd.lineweightDropdown(this.app, w);
      case "dimstyle": return dd.dimstyleDropdown(this.app, w);
      case "visualstyle": return dd.visualstyleDropdown(this.app, w);
    }
    return h("div");
  }

  private agentStatus(): HTMLElement {
    return h("div", { class: "agent-status" },
      h("div", {}, h("span", { class: "dot" }), h("span", { text: "Stopped" })),
      h("div", { style: { font: "11px var(--mono)", color: "var(--dim)" }, text: "127.0.0.1:47800" }),
      h("div", { class: "rrow" }, h("button", { class: "flatbtn", text: "Settings…", onclick: () => this.app.runCommand("OPTIONS") })));
  }

  button(it: RItem): HTMLElement {
    const app = this.app;
    const large = (it.size ?? "large") === "large" || it.kind === "menu";
    const b = h("button", { class: `rbtn ${large ? "large" : "small"}${it.width && it.width > 50 ? " wide" : ""}` },
      h("span", { class: "glyph" }, icon(it.symbol || "terminal", large ? 22 : 13, large ? 1.35 : 1.7)), h("span", { class: "t", text: tr(it.title) }));
    if (it.kind === "menu") {
      // Menus whose entries are resolved at run time (Component: COMPONENT / FURNITURE) are disabled when none can run.
      const unavailable = !!(it as any).helpUnavailable && this.menuItems(it).every((x) => x.disabled || x.separator || x.header !== undefined);
      help(b, unavailable ? (it as any).helpUnavailable : it.help || it.title);
      (b as HTMLButtonElement).disabled = unavailable;
      b.addEventListener("click", () => showMenu(this.menuItems(it), b));
    } else {
      const resolved = resolveCommand(app, it);
      const def = resolved && !resolved.startsWith("@") ? app.lookup(resolved.split(" ")[0]) : null;
      help(b, it.help || (def ? `${it.title} — ${def.summary}  [${def.name}${def.aliases?.length ? ", " + def.aliases.join(", ") : ""}]` : resolved ? it.title : `${it.title} is not available in this build`));
      const uiTarget = (it as any).ui as string | undefined;
      (b as HTMLButtonElement).disabled = !resolved && !uiTarget;
      b.addEventListener("click", () => void runEntry(app, it, resolved));
    }
    this.buttons.push({ el: b, it });
    return b;
  }

  menuItems(it: RItem): MenuItem[] {
    const out: MenuItem[] = [];
    for (const s of it.sections ?? []) {
      if (s.name && (it.sections?.length ?? 0) > 1) out.push({ header: s.name });
      else if (out.length) out.push({ separator: true });
      for (const x of s.items as any[]) {
        if (x.separator) { out.push({ separator: true }); continue; }
        if (x.dynamic) { const d = dynamicMenu(String(x.dynamic)); if (d) out.push(...d); continue; }
        if (x.dynamic || x.kind === "label" || !x.title || /\{[^}]+\}/.test(x.title)) continue; // run-time lists (dim styles, recent …)
        const r = resolveCommand(this.app, x);
        out.push({ title: x.title, symbol: x.symbol, disabled: !r && !(x.ui && uiKnown(x.ui)), action: () => void runEntry(this.app, x, r) });
      }
    }
    return out;
  }

  private updateStates() {
    const app = this.app;
    const active = app.prompt.active ? (app.prompt.command ?? "").toUpperCase() : "";
    for (const { el, it } of this.buttons) {
      let on = false;
      const c = it.command ?? "";
      if (c.startsWith("@panel:")) on = app.showPanels && app.panelTab === c.slice(7) && it.size !== "small";
      else if (c.startsWith("@mode:")) on = app.mode === c.slice(6);
      else if (c === "@scriptConsole") on = app.showScriptConsole;
      else if (c === "@cleanScreen") on = app.cleanScreen;
      else if (active && c && !c.startsWith("@")) on = [c, ...(it.names ?? [])].some((n) => n.split(" ")[0].toUpperCase() === active) || app.lookup(c)?.name === active;
      el.classList.toggle("active", on);
    }
  }
}
