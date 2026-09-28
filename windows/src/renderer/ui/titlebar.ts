// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Title bar: app icon, menu bar (the Mac app's menu bar lives here on Windows: ui/menubar.ts), centred document title, and the
// Windows caption buttons (minimise, maximise/restore, close).
import type { App } from "../app";
import { h, clear } from "../dom";
import { icon } from "../icons";
import { showMenu, MenuItem, closeMenus } from "./menu";
import { buildMenuBar, refreshMenuState } from "./menubar";
import { translateMenu } from "../workspace/l10n";

const SVGNS = "http://www.w3.org/2000/svg";
function glyph(d: string) {
  const s = document.createElementNS(SVGNS, "svg"); s.setAttribute("viewBox", "0 0 10 10");
  const p = document.createElementNS(SVGNS, "path"); p.setAttribute("d", d); p.setAttribute("stroke", "currentColor"); p.setAttribute("fill", "none"); p.setAttribute("stroke-width", "1");
  s.append(p); return s;
}
const MIN = "M0 5.5h10", MAX = "M0.5 0.5h9v9h-9z", RESTORE = "M2.5 2.5h7v7h-7z M2.5 2.5v-2h7v7h-2", CLOSE = "M0 0l10 10M10 0L0 10";

export class TitleBar {
  el: HTMLElement;
  private title = h("span", { class: "t" });
  private maxBtn: HTMLButtonElement;
  private menubar = h("div", { class: "menubar" });

  constructor(private app: App) {
    const btn = (cls: string, d: string, label: string, act: () => void) => { const b = h("button", { class: cls, "aria-label": label, title: label }, glyph(d)) as HTMLButtonElement; b.addEventListener("click", act); return b; };
    const n = app.engine.native;
    this.maxBtn = btn("max", MAX, "Maximize", async () => { const m = await n?.windowControl("maximize"); this.setMax(!!m); });
    this.el = h("div", { class: "titlebar" }, h("img", { class: "app-icon", src: "assets/app-icon.png", alt: "" }), this.menubar,
      h("div", { class: "title" }, icon("doc", 13, 1.6), this.title),
      h("div", { class: "captions" }, btn("min", MIN, "Minimize", () => n?.windowControl("minimize")), this.maxBtn, btn("close close", CLOSE, "Close", () => n?.windowControl("close"))));
    this.el.addEventListener("dblclick", (e) => { if ((e.target as HTMLElement).closest(".menubar,.captions")) return; this.maxBtn.click(); });
    n?.onWindowState((s) => { this.setMax(s.maximized); document.body.classList.toggle("inactive", !s.focused); });
    this.renderMenus();
    document.addEventListener("archi:language", () => this.renderMenus()); // LANGUAGE: translated menu titles
    (window as any).archiMenuBar = () => this.menus(); // tests: the menu tree with its actions
    app.on("doc", () => this.update());
    this.update();
  }
  private setMax(m: boolean) { this.maxBtn.replaceChildren(glyph(m ? RESTORE : MAX)); this.maxBtn.title = m ? "Restore Down" : "Maximize"; }
  update() {
    const t = this.app.windowTitle;
    this.title.textContent = t;
    document.title = t;
    this.app.engine.native?.setTitle(t);
  }

  /** File … Help, generated from the Mac menus (ui/menubar.ts). */
  private menus(): { title: string; items: MenuItem[] }[] { return translateMenu(buildMenuBar(this.app) as any[]) as { title: string; items: MenuItem[] }[]; }
  private renderMenus() {
    clear(this.menubar);
    let openIdx = -1;
    const menus = () => this.menus();
    const names = menus().map((m) => m.title);
    const keys = menuMnemonics(names);
    names.forEach((name, i) => {
      const k = keys[i], at = k ? name.toLowerCase().indexOf(k) : -1;
      // The label stays one text node (tests and accessibility read "Help", not "H"+"elp"); the access key's underline
      // is an empty mark placed under its letter while Alt is held (windows-conventions.ts showAccessKeys).
      const b = h("button", { text: name });
      if (at >= 0) { b.dataset.mnemonic = k; b.dataset.mnemonicAt = String(at); b.append(h("span", { class: "mn", "aria-hidden": "true" })); }
      const openMenu = async () => {
        openIdx = i; b.classList.add("open");
        await refreshMenuState(this.app); // Open Recent
        if (openIdx !== i) return;
        showMenu(menus()[i].items, b, { onClose: () => { b.classList.remove("open"); if (openIdx === i) openIdx = -1; } });
      };
      b.addEventListener("click", () => { if (openIdx === i) { closeMenus(); } else void openMenu(); });
      b.addEventListener("mouseenter", () => { if (openIdx >= 0 && openIdx !== i) { closeMenus(); void openMenu(); } });
      this.menubar.append(b);
    });
  }
}

/**
 * Access keys of the title-bar menus (Alt+letter; underlined while Alt is held), unique per menu as Windows requires.
 * File F, Edit E, View V, Draw D, Modify M (AutoCAD's), then Annotate N, Architecture A, Model O, Analyze Y, Tools T,
 * Window W, Help H — the three "A" menus get distinct letters. Translated or added menus take the first free letter
 * of their name.
 */
export const MENU_MNEMONICS: Record<string, string> = {
  File: "f", Edit: "e", View: "v", Draw: "d", Modify: "m", Annotate: "n", Architecture: "a", Model: "o", Analyze: "y",
  Tools: "t", Window: "w", Help: "h",
};
export function menuMnemonics(names: string[]): string[] {
  const used = new Set<string>();
  const out: string[] = names.map((n) => {
    const k = MENU_MNEMONICS[n];
    if (k && !used.has(k) && n.toLowerCase().includes(k)) { used.add(k); return k; }
    return "";
  });
  names.forEach((n, i) => {
    if (out[i]) return;
    const k = [...n.toLowerCase()].find((c) => /[a-z0-9]/.test(c) && !used.has(c)) ?? "";
    if (k) used.add(k);
    out[i] = k;
  });
  return out;
}

/** Places each menu's access-key underline under its letter (measured, so it follows the font and DPI). */
export function placeAccessKeys(root: ParentNode = document) {
  for (const b of root.querySelectorAll<HTMLElement>(".titlebar .menubar button[data-mnemonic]")) {
    const mark = b.querySelector<HTMLElement>(".mn"), text = b.firstChild;
    if (!mark || !text || text.nodeType !== Node.TEXT_NODE) continue;
    const at = Number(b.dataset.mnemonicAt ?? 0);
    const r = document.createRange();
    r.setStart(text, at); r.setEnd(text, at + 1);
    const cr = r.getBoundingClientRect(), br = b.getBoundingClientRect();
    Object.assign(mark.style, { left: `${cr.left - br.left}px`, width: `${cr.width}px`, top: `${cr.bottom - br.top + 1}px` });
  }
}
