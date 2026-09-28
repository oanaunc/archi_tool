// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Graphic Styles window (GraphicStylesUI.swift GraphicStylesView, GRAPHICSTYLES): Line Styles, Layers, Lineweight by
// Scale, Pen Sets and Filters pages. Every edit is one undo step in the drawing (graphicstyles.edit, the Mac labels).
import type { App } from "../app";
import { h, clear } from "../dom";
import { toolWindow, flatButton, iconButton, picker, segmented, textField, toggle, label, divider, spacer } from "../dialogs/ui";

interface Data {
  lineStyles: { key: string; name: string; color: string; lineweight: number | null; linetype: string }[];
  linetypes: string[]; layers: { name: string; lineStyle: string }[];
  lwTable: string; lwRows: { text: string }[];
  penSets: { name: string; pens: string }[]; activePenSet: string; penSetDisplay: boolean;
  filters: { name: string; enabled: boolean; condition: string; effect: string }[]; fields: string[]; ops: string[]; message: string;
}

export async function openGraphicStyles(app: App) {
  let data: Data | null = await app.tryCall("graphicstyles.get", {});
  if (!data) return null;
  let page = 0;
  let message = "";
  let newStyle = "", lwText = data.lwTable, penName = "", penText = "";
  const rule = { name: "Rule", field: "layer", operator: "=", value: "", color: "#FF0000", lineweight: "", halftone: false, hide: false };
  return toolWindow("graphicStyles", "Graphic Styles", 700, 480, (body) => {
    const root = h("div", { class: "gs-win" });
    const pages = h("div", { class: "gs-page" });
    const msg = h("div", { class: "gs-msg" });
    body.append(root);
    const edit = async (op: string, params: Record<string, unknown> = {}) => {
      const r = await app.tryCall("graphicstyles.edit", { op, ...params });
      if (r) { data = r; if (r.message) message = r.message; }
      await app.refresh(["drawing", "history"]);
      render();
    };
    const render = () => {
      clear(pages);
      const d = data!;
      msg.textContent = message;
      if (page === 0) {
        for (const s of d.lineStyles) {
          const color = textField("Colour (ByLayer, 1–255, r,g,b)", s.color, () => {}, { width: 110, onBlur: (v) => { if (v !== s.color) void edit("setLineStyle", { key: s.key, color: v.trim() }); }, onSubmit: (v) => void edit("setLineStyle", { key: s.key, color: v.trim() }) });
          const lwVal = s.lineweight === null ? "-1" : String(s.lineweight);
          const lw = textField("mm", lwVal, () => {}, { width: 60, onBlur: (v) => { if (v !== lwVal) setWeight(v); }, onSubmit: (v) => setWeight(v) });
          lw.title = "Lineweight in mm (−1 = ByLayer)";
          lw.classList.add("num");
          function setWeight(v: string) { const n = Number(v.replace(",", ".")); if (Number.isFinite(n)) void edit("setLineStyle", { key: s.key, lineweight: n >= 0 ? n : null }); }
          const lt = picker([{ value: "", title: "ByLayer" }, ...d.linetypes.map((t) => ({ value: t, title: t }))], s.linetype, (v) => void edit("setLineStyle", { key: s.key, linetype: v }), { width: 130 });
          pages.append(h("div", { class: "drow gs-row" }, label(s.name, { width: 130 }), color, lw, lt, iconButton("trash", "Delete the line style", () => void edit("deleteLineStyle", { key: s.key }))));
        }
        const nf = textField("New line style name", newStyle, (v) => { newStyle = v; }, { width: 200, onSubmit: () => add() });
        const add = () => { const n = newStyle.trim(); if (!n) return; newStyle = ""; void edit("addLineStyle", { name: n }); };
        pages.append(h("div", { class: "drow gs-row" }, nf, flatButton("Add", add, { compact: true })));
      } else if (page === 1) {
        const styles = d.lineStyles.map((s) => s.name);
        if (!styles.length) pages.append(label("Add line styles first.", { dim: true }));
        for (const l of d.layers) {
          pages.append(h("div", { class: "drow gs-row" }, label(l.name, { width: 180 }),
            picker([{ value: "", title: "None" }, ...styles.map((s) => ({ value: s, title: s }))], l.lineStyle, (v) => void edit("setLayerLineStyle", { layer: l.name, style: v }), { width: 180 })));
        }
      } else if (page === 2) {
        pages.append(label("Lineweight factor per view scale, e.g. 1:20=1.4; 1:50=1; 1:100=0.7; 1:200=0.5", { dim: true }));
        const f = textField("", lwText, (v) => { lwText = v; }, { onSubmit: () => void edit("setLwTable", { text: lwText }) });
        f.classList.add("gs-grow");
        pages.append(h("div", { class: "drow gs-row" }, f, flatButton("Apply", () => void edit("setLwTable", { text: lwText }), { compact: true })));
        for (const r of d.lwRows) pages.append(label(r.text, { mono: true }));
      } else if (page === 3) {
        pages.append(h("div", { class: "drow gs-row" }, label("Active pen set"),
          picker([{ value: "", title: "None" }, ...d.penSets.map((p) => ({ value: p.name, title: p.name }))], d.activePenSet, (v) => void edit("setActivePenSet", { name: v }), { width: 160 }),
          toggle("Show on screen", d.penSetDisplay, (v) => void edit("setPenSetDisplay", { on: v }))));
        for (const p of d.penSets) {
          const pens = label(p.pens, { mono: true });
          pens.classList.add("gs-trunc");
          pages.append(h("div", { class: "drow gs-row" }, label(p.name, { width: 120 }), pens, spacer(),
            flatButton("Edit", () => { penName = p.name; penText = p.pens; render(); }, { compact: true }),
            iconButton("trash", "Delete", () => void edit("deletePenSet", { name: p.name }))));
        }
        pages.append(label("Pens: number=weight[,colour]; e.g. 1=0.18;2=0.25;3=0.35,0,0,0;7=0.5", { dim: true }));
        const pt = textField("Pens", penText, (v) => { penText = v; });
        pt.classList.add("gs-grow");
        pages.append(h("div", { class: "drow gs-row" }, textField("Name", penName, (v) => { penName = v; }, { width: 120 }), pt,
          flatButton("Save", () => void edit("savePenSet", { name: penName, pens: penText }), { compact: true })));
      } else {
        d.filters.forEach((r, i) => {
          pages.append(h("div", { class: "drow gs-row" },
            toggle("", r.enabled, (v) => void edit("setFilterEnabled", { index: i, enabled: v })),
            label(r.name, { width: 110 }), label(r.condition, { mono: true }), label(r.effect, { dim: true }), spacer(),
            iconButton("arrow.up", "Higher priority", () => void edit("raiseFilter", { index: i }), { disabled: i === 0 }),
            iconButton("trash", "Delete", () => void edit("deleteFilter", { index: i }))));
        });
        pages.append(divider());
        pages.append(h("div", { class: "drow gs-row" },
          textField("Name", rule.name, (v) => { rule.name = v; }, { width: 90 }),
          picker(d.fields.map((f) => ({ value: f, title: f })), rule.field, (v) => { rule.field = v; }, { width: 100 }),
          picker(d.ops.map((o) => ({ value: o, title: o })), rule.operator, (v) => { rule.operator = v; }, { width: 90 }),
          textField("Value", rule.value, (v) => { rule.value = v; }, { width: 90 })));
        pages.append(h("div", { class: "drow gs-row" },
          textField("Colour #RRGGBB", rule.color, (v) => { rule.color = v; }, { width: 110 }),
          textField("Lineweight", rule.lineweight, (v) => { rule.lineweight = v; }, { width: 80 }),
          toggle("Halftone", rule.halftone, (v) => { rule.halftone = v; }),
          toggle("Hide", rule.hide, (v) => { rule.hide = v; }),
          flatButton("Add Rule", () => void edit("addFilter", { ...rule }), { compact: true })));
      }
    };
    const seg = segmented([{ value: 0, title: "Line Styles" }, { value: 1, title: "Layers" }, { value: 2, title: "Lineweight by Scale" }, { value: 3, title: "Pen Sets" }, { value: 4, title: "Filters" }],
      page, (v) => { page = v; render(); });
    root.append(seg, pages, msg);
    render();
    app.on("doc", () => { if (!root.isConnected) return; void app.tryCall("graphicstyles.get", {}).then((r) => { if (r && root.isConnected) { data = r; render(); } }); });
  });
}
