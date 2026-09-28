// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Outliner window (OutlinerWindow / OutlinerView, AppCommandsRound11.swift; OUTLINERPANEL): the tree of groups,
// components, blocks and model groups; click selects, double-click zooms to the object, filter by name.
import type { App } from "../app";
import { ToolWindow, field } from "../partb/ui";
import { h, clear } from "../dom";
import { icon } from "../icons";

const open = new Set<string>();
let filter = "";
let rerender: (() => void) | null = null;
let hooked = false;

export function showOutliner(app: App) {
  ToolWindow.show("outliner", "Outliner", { w: 320, h: 480, minW: 240, minH: 240 }, (w) => {
    const list = h("div", { class: "ws-outliner-list" });
    const f = field({ value: filter, placeholder: "Filter by name", flex: true, onInput: (v) => { filter = v; void render(); } });
    f.setAttribute("aria-label", "Filter outliner by name");
    w.body.append(h("div", { class: "ws-outliner" }, f, list));
    const render = async () => {
      const r = await app.tryCall("outliner.get", { filter });
      clear(list);
      const nodes: any[] = r?.nodes ?? [];
      if (!nodes.length) { list.append(h("div", { class: "pb-small pb-dim", style: { padding: "6px 2px" }, text: "No groups or components. Use MAKEGROUP or MAKECOMPONENT." })); return; }
      const add = (n: any, depth: number, path: string) => {
        const kids: any[] = n.children ?? [];
        const expanded = open.has(path) || filter.trim() !== "";
        const disc = h("span", { class: "disc" }, kids.length ? icon(expanded ? "chevron.down" : "chevron.right", 9, 2) : null);
        const row = h("div", { class: "ws-orow" + (n.selected ? " sel" : ""), style: { paddingLeft: `${4 + depth * 14}px` }, role: "button", "aria-label": `${n.kind} ${n.name}` },
          disc, h("span", { class: "sym" }, icon(String(n.symbol ?? "cube.transparent"), 12)), h("span", { class: "nm", text: String(n.name) }), h("span", { class: "kd", text: String(n.kind) }));
        disc.addEventListener("click", (e) => { e.stopPropagation(); if (open.has(path)) open.delete(path); else open.add(path); void render(); });
        row.addEventListener("click", () => void select(n, false));
        row.addEventListener("dblclick", () => void select(n, true));
        list.append(row);
        if (expanded) kids.forEach((k, i) => add(k, depth + 1, `${path}/${i}`));
      };
      nodes.forEach((n, i) => add(n, 0, `/${i}`));
    };
    const select = async (n: any, zoom: boolean) => {
      if (n.id === null || n.id === undefined) return;
      await app.tryCall("select.set", { ids: [n.id] });
      await app.refresh(["selection"]);
      if (zoom) { if (app.mode === "3D" || app.mode === "Sheet") app.setUI("mode", "2D"); await app.runCommand("ZOOM O"); }
      void render();
    };
    rerender = () => void render();
    if (!hooked) { hooked = true; app.on(["selection", "drawing"], () => { if (ToolWindow.isOpen("outliner")) rerender?.(); }); }
    void render();
    setTimeout(() => f.focus(), 0);
  });
}
