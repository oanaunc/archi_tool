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
    names.forEach((name, i) => {
      const b = h("button", { text: name });
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
