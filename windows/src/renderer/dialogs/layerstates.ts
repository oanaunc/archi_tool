// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Layer States Manager (LAYERSTATE, LayerStatesSheet in ArchiApp/Dialogs.swift): the saved states with their layer
// count and date, Restore / Update / Delete / Rename, "Save Current Layers" and Close; saved in the drawing by the engine.
import { h, clear } from "../dom";
import { icon } from "../icons";
import { sheet, flatButton, textField, note, label } from "./ui";
import { app } from "./context";

interface StateRow { name: string; layers: number; date: string | null; description: string }

export async function openLayerStates() {
  const a = app();
  let states: StateRow[] = (await a.tryCall("layerstate.list", {}))?.states ?? [];
  let selected: string | null = null;
  let renaming = "";
  let newName = "";
  const list = h("div", { class: "dlist", style: { width: "280px", height: "220px" } });
  const side = h("div", { class: "dcol", style: { gap: "6px" } });
  const nameField = textField("New state name", "", (v) => { newName = v; saveBtn.disabled = !newName.trim(); }, { width: 200, onSubmit: () => void save(newName) });
  const saveBtn = flatButton("Save Current Layers", () => void save(newName), { disabled: true });
  const refresh = async () => { await a.refresh(["layers", "drawing", "document"]); };
  const render = () => {
    clear(list);
    if (!states.length) list.append(h("div", { class: "empty", text: "No layer states yet. Save the current layer settings below." }));
    for (const st of states) {
      const when = st.date ? " · " + new Date(st.date).toLocaleString(undefined, { dateStyle: "short", timeStyle: "short" }) : "";
      const r = h("div", { class: "li" + (selected === st.name ? " sel" : "") }, icon("rectangle.stack", 13),
        h("div", {}, h("div", { class: "n", text: st.name }), h("div", { class: "s", text: `${st.layers} layers${when}` })));
      r.addEventListener("click", () => { selected = st.name; renaming = st.name; render(); });
      r.addEventListener("dblclick", () => void restore(st.name));
      list.append(r);
    }
    clear(side);
    side.append(
      flatButton("Restore", () => { if (selected) void restore(selected); }, { prominent: true, disabled: !selected }),
      flatButton("Update", () => { if (selected) void save(selected); }, { disabled: !selected, help: "Overwrite the state with the current layer settings" }),
      flatButton("Delete", () => void del(), { disabled: !selected }));
    if (selected) side.append(textField("Rename", renaming, (v) => { renaming = v; }, { width: 120, onSubmit: () => void rename() }));
  };
  async function save(raw: string) {
    const n = raw.trim();
    if (!n) return;
    const r = await a.tryCall("layerstate.save", { name: n });
    if (!r) return;
    states = r.states; selected = r.selected; renaming = selected ?? "";
    newName = ""; nameField.value = ""; saveBtn.disabled = true;
    render(); await refresh();
  }
  async function restore(n: string) {
    const r = await a.tryCall("layerstate.restore", { name: n });
    if (r) { states = r.states; render(); await refresh(); }
  }
  async function del() {
    if (!selected) return;
    const r = await a.tryCall("layerstate.delete", { name: selected });
    if (r) { states = r.states; selected = null; render(); await refresh(); }
  }
  async function rename() {
    if (!selected) return;
    const r = await a.tryCall("layerstate.rename", { name: selected, newName: renaming });
    if (r) { states = r.states; selected = r.selected; renaming = selected ?? ""; render(); await refresh(); }
  }
  render();
  const content = h("div", { class: "dcol", style: { gap: "10px" } },
    h("div", { class: "drow", style: { alignItems: "flex-start", gap: "12px", flexWrap: "nowrap" } }, list, side),
    h("div", { class: "drow", style: { gap: "6px" } }, nameField, saveBtn));
  sheet({
    title: "Layer States Manager", width: 470, content, okTitle: "Close", onOK: () => {}, onCancel: null,
    footerLeft: note("States are saved in the drawing and restore on/off, freeze, lock, plot, color, linetype and lineweight."),
  });
  void label;
}
