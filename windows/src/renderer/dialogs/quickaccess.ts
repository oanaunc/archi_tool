// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Quick access toolbar icons (QuickAccess.symbol in ArchiApp/Preferences.swift).
import { ctx } from "./context";

const MAP: Record<string, string> = {
  NEW: "doc.badge.plus", OPEN: "folder", SAVE: "square.and.arrow.down", SAVEAS: "square.and.arrow.down.on.square",
  UNDO: "arrow.uturn.backward", U: "arrow.uturn.backward", REDO: "arrow.uturn.forward", PLOT: "printer", PREVIEW: "eye",
  PUBLISH: "doc.on.doc", EXPORT: "square.and.arrow.up", MATCHPROP: "paintbrush.pointed", PROPERTIES: "slider.horizontal.3",
  LAYER: "square.3.layers.3d", QSELECT: "line.3.horizontal.decrease.circle", QSELECTDIALOG: "line.3.horizontal.decrease.circle",
  RENDER: "camera.aperture", ZOOM: "plus.magnifyingglass", REGEN: "arrow.clockwise", OPTIONS: "gearshape", WALL: "rectangle.split.2x1",
  LINE: "line.diagonal", CIRCLE: "circle", ERASE: "eraser", MOVE: "arrow.up.and.down.and.arrow.left.and.right", COPY: "plus.square.on.square",
};

export function quickAccessSymbol(name: string): string {
  const s = MAP[name.toUpperCase()];
  if (s) return s;
  switch (ctx.app?.lookup(name)?.category ?? "") {
    case "Draw": return "pencil.line";
    case "Modify": return "wand.and.rays";
    case "Annotate": return "textformat";
    case "View": return "eye";
    case "Architecture": case "BIM": return "building.2";
    default: return "terminal";
  }
}
