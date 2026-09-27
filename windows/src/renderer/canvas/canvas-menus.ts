// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Right-click menus of the 2D canvas, ported from the Mac: the shortcut menu (AppNavigation.swift ShortcutMenu,
// APP-023), the one-shot object snap override menu (CanvasView.swift snapOverrideItems, PRC-019) and the right-drag
// marking menu (RadialMenu.swift, APP-022) with the same items, sectors, sizes and colours.
import { h } from "../dom";
import { icon } from "../icons";

export type ShortcutAction =
  | { kind: "run"; line: string } | { kind: "properties" } | { kind: "quickProperties" } | { kind: "deselect" } | { kind: "selectAll" }
  | { kind: "undo" } | { kind: "redo" } | { kind: "zoomExtents" } | { kind: "repeatLast" } | { kind: "separator" }
  | { kind: "submenu"; title: string; items: ShortcutItem[] };
export interface ShortcutItem { title: string; action: ShortcutAction; enabled: boolean }

/** ShortcutMenu.items: with a selection the edit commands come first (AutoCAD "Edit" menu). */
export function shortcutItems(o: { hasSelection: boolean; lastCommand: string | null; recentInput: string[]; canUndo: boolean; canRedo: boolean; undoLabel?: string | null; redoLabel?: string | null }): ShortcutItem[] {
  const it = (title: string, action: ShortcutAction, enabled = true): ShortcutItem => ({ title, action, enabled });
  const sep = (): ShortcutItem => it("", { kind: "separator" });
  const out: ShortcutItem[] = [it(o.lastCommand ? `Repeat ${o.lastCommand}` : "Repeat", { kind: "repeatLast" }, !!o.lastCommand)];
  const recent: string[] = [];
  for (const r of [...o.recentInput].reverse()) { if (r && !recent.includes(r)) { recent.push(r); if (recent.length === 8) break; } }
  out.push(it("Recent Input", { kind: "submenu", title: "Recent Input", items: recent.map((r) => it(r, { kind: "run", line: r })) }, recent.length > 0));
  out.push(sep());
  if (o.hasSelection) {
    for (const [t, c] of [["Move", "MOVE"], ["Copy Selection", "COPY"], ["Rotate", "ROTATE"], ["Scale", "SCALE"], ["Mirror", "MIRROR"], ["Erase", "ERASE"]]) out.push(it(t, { kind: "run", line: c }));
    out.push(sep());
    out.push(it("Isolate Objects", { kind: "run", line: "ISOLATEOBJECTS" }));
    out.push(it("Select Similar", { kind: "run", line: "SELECTSIMILAR" }));
    out.push(it("Deselect All", { kind: "deselect" }));
  } else {
    out.push(it("Pan", { kind: "run", line: "PAN" }));
    out.push(it("Zoom Window", { kind: "run", line: "ZOOM W" }));
    out.push(it("Zoom Extents", { kind: "zoomExtents" }));
    out.push(it("Select All", { kind: "selectAll" }));
  }
  out.push(it("Quick Select…", { kind: "run", line: "QSELECTDIALOG" }));
  out.push(sep());
  out.push(it(o.undoLabel ? `Undo ${o.undoLabel}` : "Undo", { kind: "undo" }, o.canUndo));
  out.push(it(o.redoLabel ? `Redo ${o.redoLabel}` : "Redo", { kind: "redo" }, o.canRedo));
  out.push(sep());
  out.push(it("Quick Properties", { kind: "quickProperties" }, o.hasSelection));
  out.push(it("Properties", { kind: "properties" }));
  return out;
}

/** Snap override menu entries (title, token typed at the point prompt); null title = separator. */
export const SNAP_OVERRIDES: [string | null, string][] = [
  ["Temporary Track Point", "TT"], ["From", "FROM"], [null, ""],
  ["Endpoint", "END"], ["Midpoint", "MID"], ["Intersection", "INT"], ["Extension", "EXT"], [null, ""],
  ["Center", "CEN"], ["Geometric Center", "GCEN"], ["Quadrant", "QUA"], ["Tangent", "TAN"], [null, ""],
  ["Perpendicular", "PER"], ["Parallel", "PAR"], ["Node", "NOD"], ["Insert", "INS"], ["Nearest", "NEA"], [null, ""],
  ["None", "NON"], ["Osnap Settings…", "'OSNAP"],
];

// ---- marking menu (RadialMenu.swift) ----
export interface RadialItem { title: string; symbol: string; command: string }
export type RadialContext = "Drafting" | "Objects" | "Building elements";
export const RADIAL_THRESHOLD = 12;
export const RADIAL_RADIUS = 96;
const PREF = "archi.radialMenu";
export const radialPrefs = {
  get enabled(): boolean { try { const v = localStorage.getItem(PREF); return v === null ? true : JSON.parse(v) !== false; } catch { return true; } },
  set enabled(on: boolean) { try { localStorage.setItem(PREF, JSON.stringify(on)); } catch {} },
};

export function radialContext(selection: string[], isElement: (id: string) => boolean): RadialContext {
  if (!selection.length) return "Drafting";
  return selection.every(isElement) ? "Building elements" : "Objects";
}
const I = (title: string, symbol: string, command: string): RadialItem => ({ title, symbol, command });
/** Items clockwise from the top (N, NE, E, SE, S, SW, W, NW). */
export function radialItems(c: RadialContext): RadialItem[] {
  switch (c) {
    case "Drafting":
      return [I("Line", "line.diagonal", "LINE"), I("Polyline", "point.topleft.down.curvedto.point.bottomright.up", "PLINE"), I("Wall", "rectangle.split.3x1", "WALL"), I("Door", "door.left.hand.open", "DOOR"),
        I("Dimension", "ruler", "DIM"), I("Window", "window.vertical.open", "WINDOW"), I("Rectangle", "rectangle", "RECTANG"), I("Circle", "circle", "CIRCLE")];
    case "Objects":
      return [I("Move", "arrow.up.and.down.and.arrow.left.and.right", "MOVE"), I("Copy", "doc.on.doc", "COPY"), I("Rotate", "rotate.right", "ROTATE"), I("Offset", "square.on.square.dashed", "OFFSET"),
        I("Erase", "trash", "ERASE"), I("Trim", "scissors", "TRIM"), I("Mirror", "arrow.left.and.right.righttriangle.left.righttriangle.right", "MIRROR"), I("Properties", "slider.horizontal.3", "PROPERTIES")];
    default:
      return [I("Move", "arrow.up.and.down.and.arrow.left.and.right", "MOVE"), I("Copy", "doc.on.doc", "COPY"), I("Rotate", "rotate.right", "ROTATE"), I("Array", "square.grid.3x3", "ARRAY"),
        I("Erase", "trash", "ERASE"), I("Match Properties", "paintbrush", "MATCHPROP"), I("Mirror", "arrow.left.and.right.righttriangle.left.righttriangle.right", "MIRROR"), I("Properties", "slider.horizontal.3", "PROPERTIES")];
  }
}
/** Sector under a drag vector (screen offsets, y down): null inside the dead zone. */
export function radialSector(dx: number, dy: number): number | null {
  if (Math.hypot(dx, dy) < RADIAL_THRESHOLD) return null;
  let a = (Math.atan2(dx, -dy) * 180) / Math.PI; // clockwise from up
  if (a < 0) a += 360;
  return Math.floor((a + 22.5) / 45) % 8;
}
export function radialTooltip(it: RadialItem, lookup: (n: string) => { name: string; summary: string; aliases: string[] } | undefined): string {
  const d = lookup(it.command);
  if (!d) return it.title;
  return `${it.title} — ${d.summary} [${d.name}${d.aliases.length ? ", " + d.aliases.slice(0, 2).join(", ") : ""}]`;
}

/** The marking menu drawn around the right-drag origin (RadialMenuView). */
export class RadialMenuView {
  el: HTMLElement;
  private cells: HTMLElement[] = [];
  private center: HTMLElement;
  highlighted: number | null = null;
  constructor(readonly items: RadialItem[], x: number, y: number) {
    const r = RADIAL_RADIUS, size = 2 * (r + 34);
    this.el = h("div", { class: "radial-menu", style: { left: x - size / 2 + "px", top: y - size / 2 + "px", width: size + "px", height: size + "px" } });
    this.el.append(h("div", { class: "rm-bg", style: { width: 2 * r + 60 + "px", height: 2 * r + 60 + "px" } }));
    this.el.append(h("div", { class: "rm-dead", style: { width: 2 * RADIAL_THRESHOLD + "px", height: 2 * RADIAL_THRESHOLD + "px" } }));
    items.forEach((it, i) => {
      const a = (i * Math.PI) / 4;
      const cx = size / 2 + Math.sin(a) * r, cy = size / 2 - Math.cos(a) * r;
      const cell = h("div", { class: "rm-item", style: { left: cx - 40 + "px", top: cy - 17 + "px" } }, icon(it.symbol, 12), h("span", { text: it.title }));
      this.cells.push(cell);
      this.el.append(cell);
    });
    this.center = h("div", { class: "rm-cmd" });
    this.el.append(this.center);
  }
  setHighlighted(i: number | null) {
    if (i === this.highlighted) return;
    this.highlighted = i;
    this.cells.forEach((c, k) => c.classList.toggle("on", k === i));
    this.center.textContent = i !== null && this.items[i] ? this.items[i].command : "";
  }
}
