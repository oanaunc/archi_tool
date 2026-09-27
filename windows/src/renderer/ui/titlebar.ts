// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Title bar: app icon, menu bar (the Mac app's menu bar lives here on Windows), centred document title, and the
// Windows caption buttons (minimise, maximise/restore, close).
import type { App } from "../app";
import { h, clear } from "../dom";
import { icon } from "../icons";
import { showMenu, MenuItem, closeMenus } from "./menu";
import ui from "../data/ui.generated.json";
import { RIBBON } from "./ribbon";

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

  private menus(): { title: string; items: MenuItem[] }[] {
    const app = this.app;
    const run = (c: string) => () => app.runCommand(c);
    const fromParity = ((ui as any).menus ?? []) as any[];
    // docs/windows-parity.json menu items: {title, command, args, shortcut, submenu | items, separator, header,
    // dynamic (run-time lists: recent files, templates …), system (macOS-only such as Hide)}.
    const conv = (items: any[]): MenuItem[] => items.flatMap((it): MenuItem[] => {
      if (it.separator) return [{ separator: true }];
      if (it.header !== undefined && !it.title) return [{ header: String(it.header) }];
      if (it.dynamic) return [];
      if (it.system) {
        if (/^Quit/.test(it.title ?? "")) return [{ title: "Exit", shortcut: "Alt+F4", action: () => app.engine.native?.windowControl("close") }];
        return [];
      }
      const sub = it.submenu ?? it.items;
      let c: string | undefined = it.command;
      if (c === "@openURL") c = /guide/i.test(it.title ?? "") ? "@openURL:https://github.com/oanaunc/archi_tool/blob/main/docs/USER-GUIDE.md" : "@openURL:https://www.oanarinaldi.com";
      return [{
        title: it.title, symbol: it.symbol, shortcut: it.shortcut?.replace(/⌘/g, "Ctrl+").replace(/⇧/g, "Shift+").replace(/⌥/g, "Alt+"),
        submenu: Array.isArray(sub) ? conv(sub) : undefined,
        disabled: !!c && !c.startsWith("@") && !app.has(c.split(" ")[0]),
        action: c && !Array.isArray(sub) ? run(it.args ? `${c} ${it.args}` : c) : undefined,
      }];
    });
    const file: MenuItem[] = [
      { title: "New Window", shortcut: "Ctrl+N", action: () => app.engine.native ? app.engine.native.newWindow({ kind: "start" }) : app.newDocument() },
      { title: "New Drawing", action: () => app.newDocument("metric") }, { title: "Open…", shortcut: "Ctrl+O", action: () => app.open() },
      { title: "Start Screen", action: () => { app.showStart = true; app.emit("start"); } }, { separator: true },
      { title: "Save", shortcut: "Ctrl+S", action: () => app.save() }, { title: "Save As…", shortcut: "Ctrl+Shift+S", action: () => app.save(true) }, { separator: true },
      { title: "Import…", action: async () => { const p = await app.engine.native?.openFileDialog({ title: "Import" }); if (p) app.call("file.import", { path: p }).then(() => app.refresh(["all"])); } },
      { title: "Export", submenu: ["pdf", "dxf", "svg", "ifc", "obj", "stl", "glb", "png"].map((f) => ({ title: f.toUpperCase() + "…", action: () => app.exportAs(f) })) }, { separator: true },
      { title: "Page Setup…", action: run("PAGESETUP") }, { title: "Print…", shortcut: "Ctrl+P", action: run("PLOT") }, { separator: true },
      { title: "Close Window", shortcut: "Ctrl+W", action: () => app.engine.native?.windowControl("close") }];
    const edit: MenuItem[] = [{ title: "Undo", shortcut: "Ctrl+Z", action: () => app.undo() }, { title: "Redo", shortcut: "Ctrl+Y", action: () => app.redo() }, { separator: true },
      { title: "Cut", shortcut: "Ctrl+X", action: run("CUTCLIP") }, { title: "Copy", shortcut: "Ctrl+C", action: run("COPYCLIP") }, { title: "Paste", shortcut: "Ctrl+V", action: run("PASTECLIP") },
      { title: "Erase", shortcut: "Del", action: run("ERASE") }, { separator: true }, { title: "Select All", shortcut: "Ctrl+A", action: () => app.selectAll() },
      { title: "Quick Select…", action: run("QSELECTDIALOG") }, { separator: true }, { title: "Find and Replace…", action: run("FIND") }, { title: "Options…", shortcut: "Ctrl+,", action: run("OPTIONS") }];
    const view: MenuItem[] = [...(["2D", "3D", "Split", "Sheet"] as const).map((m) => ({ title: { "2D": "2D Plan", "3D": "3D Model", Split: "Split", Sheet: "Sheet" }[m], checked: app.mode === m, action: () => app.setUI("mode", m) })),
      { separator: true }, { title: "Zoom Extents", action: () => app.canvas?.zoomExtents() }, { title: "Zoom In", shortcut: "Ctrl+=", action: () => app.canvas?.zoomBy(1.5) }, { title: "Zoom Out", shortcut: "Ctrl+-", action: () => app.canvas?.zoomBy(1 / 1.5) },
      { separator: true }, { title: app.showPanels ? "Hide Panels" : "Show Panels", action: () => app.setUI("showPanels", !app.showPanels) },
      { title: "Clean Screen", shortcut: "Ctrl+0", checked: app.cleanScreen, action: () => app.action("@cleanScreen") }, { title: "Command Search…", shortcut: "Ctrl+K", action: () => document.dispatchEvent(new CustomEvent("archi:commandSearch")) }];
    const cats = fromParity.length ? fromParity.filter((m) => !["File", "Edit", "View", "Window", "Help", "Oanarina Archi Tool"].includes(m.menu ?? m.title)).map((m) => ({ title: m.menu ?? m.title, items: conv(m.items ?? []) })) : [];
    const help: MenuItem[] = [{ title: "Command Reference", action: run("COMMANDREFERENCE") }, { title: "Keyboard Shortcuts", action: run("SHORTCUTS") }, { title: "User Guide", action: run("HELP") }, { separator: true },
      { title: "Oanarina Archi Tool Website", action: () => app.engine.native?.openExternal("https://www.oanarinaldi.com/archi-tool.html") }, { title: "About Oanarina Archi Tool", action: run("ABOUT") }];
    const out = [{ title: "File", items: file }, { title: "Edit", items: edit }, { title: "View", items: view }, ...cats];
    if (!cats.length) for (const t of RIBBON.filter((t) => ["Insert", "Annotate", "Architecture", "Modeling"].includes(t.tab))) out.push({ title: t.tab, items: t.groups.flatMap((g, i) => [...(i ? [{ separator: true } as MenuItem] : []), ...g.items.filter((x) => x.command && !x.command.startsWith("@") && x.kind !== "dropdown").map((x) => ({ title: x.title, symbol: x.symbol, action: run(x.args ? `${x.command} ${x.args}` : x.command!) }))]) });
    out.push({ title: "Window", items: [{ title: "Minimize", action: () => app.engine.native?.windowControl("minimize") }, { title: "Maximize", action: () => app.engine.native?.windowControl("maximize") }, { separator: true }, { title: "New Window", action: () => app.engine.native?.newWindow({ kind: "start" }) }] });
    out.push({ title: "Help", items: help });
    return out;
  }
  private renderMenus() {
    clear(this.menubar);
    let openIdx = -1;
    const menus = () => this.menus();
    const names = menus().map((m) => m.title);
    names.forEach((name, i) => {
      const b = h("button", { text: name });
      const openMenu = () => { openIdx = i; b.classList.add("open"); showMenu(menus()[i].items, b, { onClose: () => { b.classList.remove("open"); if (openIdx === i) openIdx = -1; } }); };
      b.addEventListener("click", () => { if (openIdx === i) { closeMenus(); } else openMenu(); });
      b.addEventListener("mouseenter", () => { if (openIdx >= 0 && openIdx !== i) { closeMenus(); openMenu(); } });
      this.menubar.append(b);
    });
  }
}
