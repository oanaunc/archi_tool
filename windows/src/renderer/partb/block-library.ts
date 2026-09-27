// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Block library (BlockLibraryPanel.swift, BLOCKPALETTE): library folders of .archi / .dxf drawings, each file and each
// block inside it with a thumbnail rendered from its draw list, search, Folder / Favourites / Recent, drag onto the
// drawing to insert, double-click to insert at the view centre (one undo step, library.insert).
import type { App } from "../app";
import { h, clear, button, iconButton, menuButton, segmented, spacer, ToolWindow, ico, help, load, store, showMenu, type MenuItem } from "./ui";
import * as N from "./native";
import { paintFitted } from "./plan-paint";
import type { PlanHooks } from "./index";

export interface LibItem { file: string; block: string | null; name: string; folder: string }
const key = (i: LibItem) => i.file + "\u001F" + (i.block ?? "");
export const DRAG_TYPE = "application/x-archi-libblock";

const Store = {
  get folders(): string[] { return load("blockLibrary.folders", []); }, set folders(v: string[]) { store("blockLibrary.folders", v); },
  get current(): string | null { return load("blockLibrary.current", null) ?? this.folders[0] ?? null; }, set current(v: string | null) { store("blockLibrary.current", v); },
  get favourites(): LibItem[] { return load("blockLibrary.favourites", []); }, set favourites(v: LibItem[]) { store("blockLibrary.favourites", v); },
  get recents(): LibItem[] { return load("blockLibrary.recents", []); }, set recents(v: LibItem[]) { store("blockLibrary.recents", v); },
};

/** Case-insensitive search on item name, file name and folder (all words must match): BlockLibrary.search. */
export function searchItems(items: LibItem[], query: string): LibItem[] {
  const words = query.toLowerCase().split(" ").filter(Boolean);
  if (!words.length) return items;
  return items.filter((i) => { const hay = `${i.name} ${N.basename(i.file)} ${i.folder}`.toLowerCase(); return words.every((w) => hay.includes(w)); });
}

const thumbs = new Map<string, any>();
let scanCache: { folder: string; items: LibItem[] } | null = null;

export async function insertLibraryItem(app: App, i: LibItem, at: [number, number]) {
  try {
    const r = await app.call("library.insert", { file: i.file, block: i.block, x: at[0], y: at[1] });
    if (r?.id !== undefined) {
      const k = key(i);
      Store.recents = [i, ...Store.recents.filter((x) => key(x) !== k)].slice(0, 12);
    }
  } catch { /* printed by app.call */ }
  await app.refresh(["document", "selection"]);
}

export function showBlockLibrary(app: App, plan: PlanHooks) {
  ToolWindow.show("blockLibrary", "Block Library", { w: 560, h: 560, minW: 420, minH: 360 }, (w) => { new BlockLibraryView(app, plan, w.body); });
}

class BlockLibraryView {
  private query = "";
  private scope: "Folder" | "Favourites" | "Recent" = "Folder";
  private selected: string | null = null;
  private items: LibItem[] = [];
  private head = h("div", { class: "pb-row", style: { padding: "8px", gap: "6px" } });
  private grid = h("div", { class: "pb-grid", style: { gridTemplateColumns: "repeat(auto-fill, minmax(128px, 1fr))" } });
  private body = h("div", { class: "pb-scroll", style: { flex: "1" } });
  private foot = h("div", { class: "pb-small pb-dim", style: { padding: "6px" } });

  constructor(private app: App, private plan: PlanHooks, host: HTMLElement) {
    const search = h("input", { class: "pb-field", placeholder: "Search blocks, files and folders", style: { flex: "1", border: "0", background: "transparent" } }) as HTMLInputElement;
    search.addEventListener("input", () => { this.query = search.value; this.renderGrid(); });
    search.addEventListener("keydown", (e) => e.stopPropagation());
    const searchRow = h("div", { class: "pb-row pb-field", style: { margin: "0 8px", height: "26px", padding: "0 6px" } }, h("span", { class: "pb-dim", style: { display: "flex" } }, ico("magnifyingglass", 12)), search);
    host.append(this.head, searchRow, h("div", { class: "pb-hsep", style: { marginTop: "6px" } }), this.body, h("div", { class: "pb-hsep" }), this.foot);
    this.renderHead();
    this.rescan();
  }

  private renderHead() {
    clear(this.head);
    const cur = Store.current;
    const label = cur ? N.basename(cur) : "Choose a folder";
    const folderMenu = (): MenuItem[] => {
      const items: MenuItem[] = Store.folders.map((f) => ({ title: f, checked: f === Store.current, action: () => { Store.current = f; this.renderHead(); this.rescan(); } }));
      items.push({ separator: true }, { title: "Add Library Folder…", action: () => this.chooseFolder() });
      if (cur) items.push({ title: `Remove ${N.basename(cur)} from the List`, action: () => { Store.folders = Store.folders.filter((x) => x !== cur); Store.current = Store.folders[0] ?? null; this.renderHead(); this.rescan(); } });
      return items;
    };
    const fm = menuButton(label, "folder", folderMenu);
    fm.style.maxWidth = "180px";
    this.head.append(fm,
      iconButton("folder.badge.plus", "Add a library folder of .archi / .dxf drawings", () => this.chooseFolder()),
      iconButton("arrow.clockwise", "Rescan the folder", () => { scanCache = null; thumbs.clear(); this.rescan(); }),
      segmented(["Folder", "Favourites", "Recent"], this.scope, (v) => { this.scope = v; this.renderGrid(); }));
    (this.head.lastElementChild as HTMLElement).style.width = "220px";
  }

  private async chooseFolder() {
    const f = await N.chooseFolder("Choose a folder of drawings (.archi, .dxf) to browse as a block library");
    if (!f) return;
    if (!Store.folders.includes(f)) Store.folders = [...Store.folders, f];
    Store.current = f;
    this.renderHead();
    scanCache = null;
    this.rescan();
  }

  private async rescan() {
    const cur = Store.current;
    if (!cur) { this.items = []; this.renderGrid(); return; }
    if (scanCache?.folder === cur) { this.items = scanCache.items; this.renderGrid(); return; }
    const r = await this.app.tryCall("library.scan", { folder: cur });
    this.items = (r?.items ?? []).map((x: any) => ({ file: x.file, block: x.block ?? null, name: x.name, folder: x.folder ?? "" }));
    scanCache = { folder: cur, items: this.items };
    this.renderGrid();
  }

  private shown(): LibItem[] {
    const src = this.scope === "Favourites" ? Store.favourites : this.scope === "Recent" ? Store.recents : this.items;
    return searchItems(src, this.query);
  }

  private renderGrid() {
    clear(this.body);
    if (!Store.current && this.scope === "Folder") {
      this.body.append(h("div", { class: "pb-empty", style: { height: "100%" } }, h("span", { class: "pb-dim" }, ico("books.vertical", 34, 1.4)),
        h("div", { text: "Choose a folder of drawings to use as a block library." }), button("Choose Folder…", { onClick: () => this.chooseFolder() })));
      this.foot.textContent = "0 item(s) · drag onto the drawing to insert · double-click inserts at the view centre";
      return;
    }
    clear(this.grid);
    const list = this.shown();
    for (const i of list) this.grid.append(this.cell(i));
    this.body.append(this.grid);
    this.foot.textContent = `${list.length} item(s) · drag onto the drawing to insert · double-click inserts at the view centre`;
  }

  private cell(i: LibItem): HTMLElement {
    const k = key(i);
    const fav = Store.favourites.some((x) => key(x) === k);
    const thumb = h("div", { class: "thumb" });
    const star = h("button", { class: "star pb-ibtn", style: { color: fav ? "var(--accent)" : "var(--dim)" } }, ico(fav ? "star.fill" : "star", 12));
    help(star, fav ? "Remove from favourites" : "Add to favourites");
    star.addEventListener("click", (e) => { e.stopPropagation(); this.toggleFav(i); });
    const el = h("div", { class: "pb-tile" + (this.selected === k ? " sel" : ""), draggable: "true", "data-key": k }, thumb, star,
      h("div", { class: "n", text: i.name }), h("div", { class: "s", text: i.block === null ? (i.folder || "drawing") : N.stem(i.file) }));
    help(el, `${i.file}${i.block ? " ▸ " + i.block : ""}`);
    el.addEventListener("click", () => { this.selected = k; for (const c of this.grid.children) c.classList.toggle("sel", (c as HTMLElement).dataset.key === k); });
    el.addEventListener("dblclick", () => this.insertAtCentre(i));
    el.addEventListener("dragstart", (e) => { e.dataTransfer?.setData(DRAG_TYPE, JSON.stringify(i)); e.dataTransfer?.setData("text/plain", "archi-libblock:" + k); });
    el.addEventListener("contextmenu", (e) => {
      e.preventDefault();
      showMenu([{ title: "Insert at View Centre", action: () => this.insertAtCentre(i) }, { title: fav ? "Remove from Favourites" : "Add to Favourites", action: () => this.toggleFav(i) },
        { title: "Show in Explorer", action: () => N.reveal(this.app, i.file) }], { x: e.clientX, y: e.clientY });
    });
    this.thumbnail(i, thumb);
    return el;
  }

  private async thumbnail(i: LibItem, host: HTMLElement) {
    const k = key(i);
    let data = thumbs.get(k);
    if (data === undefined) { data = await this.app.tryCall("library.preview", { file: i.file, block: i.block }); thumbs.set(k, data); }
    const cv = h("canvas") as HTMLCanvasElement;
    if (data && paintFitted(cv, data, 120, 90, { background: null, margin: 0.06, bounds: data.bounds ?? null })) host.append(cv);
    else host.append(h("span", { class: "pb-dim" }, ico("questionmark.square.dashed", 28, 1.4)));
  }

  private toggleFav(i: LibItem) {
    const k = key(i);
    const f = Store.favourites;
    Store.favourites = f.some((x) => key(x) === k) ? f.filter((x) => key(x) !== k) : [...f, i];
    this.renderGrid();
  }

  private insertAtCentre(i: LibItem) { insertLibraryItem(this.app, i, this.plan.center()); }
}
