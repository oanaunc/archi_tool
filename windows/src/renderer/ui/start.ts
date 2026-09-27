// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Start screen (StartView.swift): start tiles, templates, sample projects with plan thumbnails, recent drawings.
import type { App } from "../app";
import { h, clear } from "../dom";
import { icon } from "../icons";
import { help, showMenu } from "./menu";
import { paintThumbnail } from "../canvas/thumbnail";
import { prefs } from "../prefs";
import { listTemplates, newFromTemplate, openTemplateFile, revealTemplatesFolder } from "../dialogs";

const TEMPLATES = [
  { id: "metric", name: "Metric", subtitle: "Millimetres, standard layers", symbol: "square.and.pencil" },
  { id: "metric-architectural", name: "Metric Architectural", subtitle: "AIA-style layers, 1:20–1:200 dimension styles", symbol: "ruler" },
  { id: "imperial", name: "Imperial", subtitle: "Inches, architectural dimensions", symbol: "ruler" },
  { id: "building", name: "Building", subtitle: "Levels, structural grid and sheets", symbol: "building.2" },
];
const SAMPLES = [{ name: "Cedar House", subtitle: "Contemporary house with materials" }, { name: "Nordic House", subtitle: "Nordic timber house" }];

export class StartScreen {
  el: HTMLElement;
  constructor(private app: App) {
    this.el = h("div", { class: "start" });
    this.el.style.display = "none";
    app.on("start", () => this.render());
  }
  async render() {
    const app = this.app;
    this.el.style.display = app.showStart ? "" : "none";
    if (!app.showStart) return;
    clear(this.el);
    const tile = (sym: string, title: string, sub: string, act: () => void) => {
      const b = h("button", { class: "tile" }, h("span", { class: "ico" }, icon(sym, 19, 1.5)), h("span", {}, h("div", { class: "tt", text: title }), h("div", { class: "st", text: sub })),
        h("span", { class: "go" }, icon("chevron.right", 11, 2)));
      b.addEventListener("click", act);
      return b;
    };
    const left = h("div", { class: "left" },
      h("div", { class: "brand" }, h("img", { src: "assets/app-icon.png", alt: "" }), h("div", {}, h("div", { class: "n", text: "Oanarina Archi Tool" }), h("div", { class: "s", text: "Drafting and building design for Windows" }))),
      h("div", { class: "sec", text: "START", style: { paddingTop: "4px" } }),
      h("div", { class: "tiles" },
        tile("square.and.pencil", "New Drawing", ["inches", "feet"].includes(prefs.get("defaultUnits")) ? "Imperial" : `Metric · ${prefs.get("defaultUnits")}`, () => app.newDocument("metric")),
        tile("folder", "Open…", ".archi projects and DXF drawings", () => app.open()),
        tile("house.lodge", "Build Sample House", "Watch a house being drawn by commands", () => app.buildSampleHouse())),
      h("div", { class: "tip" }, icon("keyboard", 12), h("span", { text: "Tip: just start typing — LINE, WALL, DOOR, ROOM… Space or Enter repeats the last command." })));
    const right = h("div", { class: "right" });
    const hdr = (title: string, ...trailing: HTMLElement[]) => h("div", { class: "shdr" }, h("span", { class: "sec", text: title }), ...trailing);
    const folderBtn = h("button", { class: "flatbtn", text: "Folder" }); help(folderBtn, "Put .archi files here to use them as templates (or SAVEASTEMPLATE)");
    folderBtn.addEventListener("click", () => void revealTemplatesFolder());
    const openT = h("button", { class: "flatbtn", text: "Open Template…" }); help(openT, "Start a new drawing from any .architemplate file");
    openT.addEventListener("click", () => void openTemplateFile());
    right.append(hdr("TEMPLATES", folderBtn, openT));
    const tg = h("div", { class: "grid t" });
    for (const t of await listTemplates()) {
      const c = h("button", { class: "card2" }, h("div", { class: "thumb" }, icon(t.symbol, 24, 1.6)), h("div", { class: "n", text: t.name }), h("div", { class: "d", text: t.subtitle }));
      c.addEventListener("click", () => void newFromTemplate(t.id, true));
      tg.append(c);
    }
    right.append(tg, hdr("SAMPLE PROJECTS"));
    const sg = h("div", { class: "grid s" });
    for (const s of SAMPLES) {
      const th = h("div", { class: "thumb big" });
      const c = h("button", { class: "card2" }, th, h("div", { class: "n" }, icon("star.fill", 10), h("span", { text: s.name })), h("div", { class: "d", text: s.subtitle }));
      c.addEventListener("click", () => app.openSample(s.name));
      sg.append(c);
      paintThumbnail(th, `assets/samples/${s.name}.thumb.json`, "house");
    }
    right.append(sg);
    const recents = (await app.engine.native?.recentFiles()) ?? [];
    const clearBtn = h("button", { class: "flatbtn", text: "Clear" });
    clearBtn.addEventListener("click", async () => { await app.engine.native?.clearRecent(); this.render(); });
    right.append(hdr("RECENT", ...(recents.length ? [clearBtn] : [])));
    if (!recents.length) right.append(h("div", { class: "none" }, icon("clock", 13), h("span", { text: "No recent documents" })));
    else {
      const rg = h("div", { class: "grid r" });
      for (const r of recents) {
        const name = r.path.split(/[\\/]/).pop()!.replace(/\.[^.]+$/, "");
        const c = h("button", { class: "card2" }, h("div", { class: "thumb big" }, icon("building.columns", 24, 1.4)), h("div", { class: "n", text: name }),
          h("div", { class: "d", text: r.modified ? new Date(r.modified).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" }) : r.path }));
        help(c, r.path);
        c.addEventListener("click", () => app.open(r.path));
        c.addEventListener("contextmenu", (e) => { e.preventDefault(); showMenu([{ title: "Open", action: () => app.open(r.path) }], { x: e.clientX, y: e.clientY }); });
        rg.append(c);
      }
      right.append(rg);
    }
    const close = h("button", { class: "iconbtn close" }, icon("xmark", 13, 2)); help(close, "Continue with an empty drawing");
    close.addEventListener("click", () => { app.closeStart(); app.canvas?.focus(); });
    this.el.append(h("div", { class: "card" }, left, h("div", { class: "vsep" }), right, close));
  }
}
