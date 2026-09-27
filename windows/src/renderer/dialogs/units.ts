// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Drawing Units (UNITS button, UnitsSheet in ArchiApp/MainWindow.swift) and Drafting Settings (DSETTINGS,
// DraftingSettingsSheet): same fields, order, ranges and defaults; the engine applies them (units.set: one "Units"
// undo step; drafting.set: the session's drafting settings).
import { h } from "../dom";
import { sheet, picker, stepper, radioGroup, toggle, numberField, flatButton, row, col, label, note, divider, Option } from "./ui";
import { app } from "./context";

interface UnitsInfo {
  units: string; lunits: number; luprec: number; aunits: number; auprec: number;
  unitList: { value: string; title: string }[]; linearTypes: Option<number>[]; angularTypes: Option<number>[];
  linearPrecisionLabel: string; angularPrecisionLabel: string; sample: string; note: string;
}

export async function openUnits() {
  const a = app();
  const info: UnitsInfo | null = await a.tryCall("units.get", {});
  if (!info) { a.print("Drawing units need archi-engine."); return; }
  const s = { units: info.units, lunits: info.lunits, luprec: info.luprec, aunits: info.aunits, auprec: info.auprec };
  const sample = h("div", { class: "sample", text: info.sample });
  const unitNote = note(info.note);
  let lprecStep: HTMLElement, aprecStep: HTMLElement;
  let lprecLabel = info.linearPrecisionLabel, aprecLabel = info.angularPrecisionLabel;
  const refresh = async () => {
    const r: UnitsInfo | null = await a.tryCall("units.get", s);
    if (!r) return;
    sample.textContent = r.sample; unitNote.textContent = r.note;
    lprecLabel = r.linearPrecisionLabel; aprecLabel = r.angularPrecisionLabel;
    (lprecStep as any).setLabel(); (aprecStep as any).setLabel();
  };
  lprecStep = stepper(() => lprecLabel, s.luprec, 0, 8, (v) => { s.luprec = v; void refresh(); });
  aprecStep = stepper(() => aprecLabel, s.auprec, 0, 8, (v) => { s.auprec = v; void refresh(); });
  const content = h("div", { class: "dcol", style: { width: "360px", gap: "10px" } },
    h("div", { class: "drow", style: { alignItems: "flex-start", gap: "18px", flexWrap: "nowrap" } },
      col(label("Length", { bold: true }), picker(info.linearTypes, s.lunits, (v) => { s.lunits = v; void refresh(); }, { label: "Type", width: 120 }), lprecStep),
      col(label("Angle", { bold: true }), picker(info.angularTypes, s.aunits, (v) => { s.aunits = v; void refresh(); }, { label: "Type", width: 130 }), aprecStep)),
    sample,
    divider(),
    h("div", { class: "drow", style: { alignItems: "flex-start" } }, label("Insertion units"),
      radioGroup(info.unitList.map((u) => ({ value: u.value, title: u.title })), s.units, (v) => { s.units = v; void refresh(); })),
    unitNote);
  sheet({
    title: "Drawing Units", content,
    onCancel: () => {},
    onOK: async () => { await a.tryCall("units.set", s); await a.refresh(["document", "sysvars"]); },
  });
}

interface Drafting {
  showGrid: boolean; gridSnap: boolean; gridSpacing: number; ortho: boolean; polarTracking: boolean; polarIncrement: number;
  dynamicInput: boolean; lineweightDisplay: boolean; textHeight: number; wallThickness: number; wallHeight: number;
  objectSnap: boolean; snapModes: string[]; snapKinds: string[]; polarIncrements: number[];
}

export async function openDraftingSettings() {
  const a = app();
  const d: Drafting | null = await a.tryCall("drafting.get", {});
  if (!d) { a.print("Drafting settings need archi-engine."); return; }
  const s = { ...d, snapModes: [...d.snapModes] };
  const num = (key: "gridSpacing" | "textHeight" | "wallThickness" | "wallHeight") => numberField(s[key], (v) => { s[key] = v; }, { width: 80, positive: true });
  const snapBox = h("div", { class: "dcol", style: { gap: "6px" } });
  const renderSnaps = () => {
    snapBox.replaceChildren(...d.snapKinds.map((k) => toggle(k[0].toUpperCase() + k.slice(1), s.snapModes.includes(k), (on) => {
      s.snapModes = on ? [...s.snapModes, k] : s.snapModes.filter((x) => x !== k);
    })));
  };
  renderSnaps();
  const left = col(
    label("Snap and Grid", { bold: true }),
    toggle("Grid display (F7)", s.showGrid, (v) => { s.showGrid = v; }),
    toggle("Grid snap (F9)", s.gridSnap, (v) => { s.gridSnap = v; }),
    row(label("Grid spacing"), num("gridSpacing")),
    divider(),
    label("Polar Tracking", { bold: true }),
    toggle("Ortho (F8)", s.ortho, (v) => { s.ortho = v; }),
    toggle("Polar tracking (F10)", s.polarTracking, (v) => { s.polarTracking = v; }),
    picker(d.polarIncrements.map((x) => ({ value: x, title: `${x}°` })), s.polarIncrement, (v) => { s.polarIncrement = v; }, { label: "Increment", width: 100 }),
    divider(),
    toggle("Dynamic input (F12)", s.dynamicInput, (v) => { s.dynamicInput = v; }),
    toggle("Show lineweights", s.lineweightDisplay, (v) => { s.lineweightDisplay = v; }),
    row(label("Text height"), num("textHeight")),
    row(label("Wall thickness"), num("wallThickness")),
    row(label("Wall height"), num("wallHeight")));
  left.style.width = "230px";
  left.querySelectorAll(".hsep").forEach((e) => ((e as HTMLElement).style.width = "100%"));
  const right = col(
    toggle("Object snap (F3)", s.objectSnap, (v) => { s.objectSnap = v; }, { bold: true }),
    snapBox,
    row(flatButton("Select All", () => { s.snapModes = [...d.snapKinds]; renderSnaps(); }, { compact: true }), flatButton("Clear All", () => { s.snapModes = []; renderSnaps(); }, { compact: true })));
  right.style.gap = "6px";
  const content = h("div", { class: "drow", style: { alignItems: "flex-start", gap: "24px", width: "480px", flexWrap: "nowrap" } }, left, right);
  sheet({
    title: "Drafting Settings", content,
    onCancel: () => {},
    onOK: async () => {
      const { snapKinds: _k, polarIncrements: _p, ...values } = s;
      void _k; void _p;
      await a.tryCall("drafting.set", values);
      await a.refresh(["sysvars", "drawing"]);
    },
  });
}
