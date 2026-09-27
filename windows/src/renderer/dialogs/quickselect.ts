// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Quick Select (QSELECTDIALOG, QuickSelectSheet in ArchiApp/Dialogs.swift): Apply to, Object type, Property, Operator,
// Value (with the layer list for "layer"), How to apply, and the live match count; the engine matches (qselect.run).
import { h } from "../dom";
import { icon } from "../icons";
import { showMenu } from "../ui/menu";
import { sheet, picker, radioGroup, textField, label, Option } from "./ui";
import { app } from "./context";

interface QSOptions { types: Option[]; properties: Option[]; operators: Option[]; layers: string[]; selectionCount: number; scope: number }

export async function openQuickSelect() {
  const a = app();
  const o: QSOptions | null = await a.tryCall("qselect.options", {});
  if (!o) { a.print("Quick Select needs archi-engine."); return; }
  const s = { scope: o.selectionCount > 1 ? 0 : 0, type: "*", property: "*", op: "=", value: "", mode: "New" };
  const count = h("span", { class: "match" });
  let seq = 0;
  const update = async () => {
    const n = ++seq;
    const r = await a.tryCall("qselect.run", s);
    if (n !== seq || !r) return;
    count.textContent = `${r.count} object(s) match`;
    count.classList.toggle("hit", r.count > 0);
  };
  const grid = h("div", { class: "dgrid" });
  const opRow: HTMLElement[] = [];
  const valueField = textField("", s.value, (v) => { s.value = v; void update(); }, { width: 200 });
  const setPlaceholder = () => { valueField.placeholder = s.property === "layer" ? "Layer name or wildcard (A-*)" : "Value (wildcards * ? allowed for text)"; };
  setPlaceholder();
  const layerMenu = h("button", { class: "iconbtn", "aria-label": "Layers" }, icon("chevron.down", 10, 2));
  layerMenu.addEventListener("click", () => showMenu(o.layers.map((l) => ({ title: l, action: () => { s.value = l; valueField.value = l; void update(); } })), layerMenu));
  const valueCell = h("div", { class: "drow", style: { gap: "4px", flexWrap: "nowrap" } }, valueField, layerMenu);
  const scopeOpts: Option<number>[] = [{ value: 0, title: "Current level" }, { value: 1, title: `Current selection (${o.selectionCount})` }];
  const showOps = () => {
    for (const e of opRow) e.style.display = s.property === "*" ? "none" : "";
    layerMenu.style.display = s.property === "layer" ? "" : "none";
    setPlaceholder();
  };
  const opLabel = label("Operator"), opPicker = picker(o.operators, s.op, (v) => { s.op = v; void update(); }, { width: 240 });
  const valLabel = label("Value");
  opRow.push(opLabel, opPicker, valLabel, valueCell);
  grid.append(
    label("Apply to"), picker(scopeOpts, s.scope, (v) => { s.scope = v; void update(); }, { width: 240 }),
    label("Object type"), picker(o.types, s.type, (v) => { s.type = v; void update(); }, { width: 240 }),
    label("Property"), picker(o.properties, s.property, (v) => { s.property = v; showOps(); void update(); }, { width: 240 }),
    opLabel, opPicker, valLabel, valueCell,
    label("How to apply"), radioGroup([{ value: "New", title: "Replace the selection" }, { value: "Append", title: "Add to the selection" }, { value: "Exclude", title: "Remove from the selection" }], s.mode, (v) => { s.mode = v; }));
  grid.style.alignItems = "center";
  showOps();
  sheet({
    title: "Quick Select", width: 440, content: grid, footerLeft: count, okTitle: "Select",
    onCancel: () => {},
    onOK: async () => { await a.tryCall("qselect.run", { ...s, apply: true }); await a.refresh(["selection"]); },
  });
  void update();
}
