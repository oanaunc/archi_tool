// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Page Setup (PAGESETUP, Ctrl+Shift+P; PageSetupSheet + PageSetupForm in ArchiApp/PlotExtras.swift): paper and
// orientation of a sheet, plot style, plot style tables, lineweight scale, plot stamp, and for model space the paper,
// orientation, plot area, exact fit and scale. Stored in the drawing by the engine (pagesetup.set, one undo step).
import { h, clear } from "../dom";
import { sheet, picker, segmented, slider, toggle, textField, flatButton, note, label, row, divider, Option } from "./ui";
import { app } from "./context";

interface Setup {
  colorMode: string; lineweightScale: number; plotStamp: boolean; stampText?: string; modelPaper: string; modelPortrait: boolean; modelScale?: number;
  plotStyleTable?: string; namedStyleTable?: string; plotArea: string; plotWindow?: number[]; exactFit: boolean;
}
interface PageSetupInfo {
  isSheet: boolean; layout: number | null; title: string; paper?: string; portrait?: boolean;
  papers: { name: string; width: number; height: number; label: string; modelLabel: string }[];
  setup: Setup; scaleText: string; colorModes: string[]; plotAreas: string[]; tables: string[]; namedTables: string[];
  scales: Option[]; stampTemplate: string; stampFields: string[];
  hasSection?: boolean; sectionStyle?: SectionStyle | null;
  presets?: { name: string; preset: { settings: string; paper: { name: string; width: number; height: number }; sectionStyle?: SectionStyle } }[];
  layouts?: { index: number; name: string }[];
}
interface SectionStyle { shaded: boolean; lines: { color?: { r: number; g: number; b: number; a: number }; cutFill?: { r: number; g: number; b: number; a: number }; cutLineweight?: number; projectionLineweight?: number } }

/** Visible 2D view in drawing units ([x0, y0, x1, y1]) for the Display plot area; set by index.ts. */
export const pageSetupHooks: { displayBox: () => number[] | null } = { displayBox: () => null };

/** layout: sheet index (0-based) or null for model space. */
export async function openPageSetup(layout: number | null) {
  const a = app();
  const info: PageSetupInfo | null = await a.tryCall("pagesetup.get", layout === null ? {} : { layout });
  if (!info) { a.print("Page setup needs archi-engine."); return; }
  const setup: Setup = { ...info.setup };
  let paper = info.paper ?? "A3", portrait = !!info.portrait, scaleText = info.scaleText;
  let sectionOn = !!info.sectionStyle;
  let section: SectionStyle = structuredClone(info.sectionStyle ?? { shaded: true, lines: { color: { r: 0, g: 0, b: 0, a: 1 }, cutFill: { r: .62, g: .62, b: .62, a: 1 }, cutLineweight: .5, projectionLineweight: .25 } });
  let presets = info.presets ?? [], selected = "", presetName = "", presetSource = "";
  const targets = new Set<number>(info.layout === null ? [] : [info.layout]);
  const refreshPresets = async () => { const result = await a.tryCall("pagepresets.list", {}); presets = result?.presets ?? presets; render(); };
  const reload = async () => { await a.refresh(["document", "drawing"]); handle.close(); await openPageSetup(layout); };
  const body = h("div", { class: "dcol", style: { gap: "10px", width: "420px" } });
  const lw = label(`×${setup.lineweightScale.toFixed(2)}`, { mono: true, width: 44 });
  lw.style.textAlign = "right";
  const render = () => {
    clear(body);
    if (info.isSheet) {
      body.append(note("NAMED PAGE SETUPS"), row(
        picker([{ value: "", title: "Choose…" }, ...presets.map((p) => ({ value: p.name, title: p.name }))], selected, (v) => { selected = v; render(); }, { label: "Setup", width: 180 }),
        flatButton("Load", () => {
          const p = presets.find((p) => p.name === selected)?.preset; if (!p) return;
          Object.keys(setup).forEach((key) => delete (setup as any)[key]); Object.assign(setup, JSON.parse(p.settings));
          presetSource = selected;
          paper = p.paper.name; portrait = p.paper.height > p.paper.width;
          if (!info.papers.some((item) => item.name === paper)) info.papers.push({ ...p.paper, label: `${paper} (${p.paper.width}×${p.paper.height} mm)`, modelLabel: paper });
          sectionOn = !!p.sectionStyle; if (p.sectionStyle) section = structuredClone(p.sectionStyle); render();
        }, { disabled: !selected }),
        flatButton("Delete", async () => { await a.tryCall("pagepresets.delete", { name: selected }); selected = ""; await refreshPresets(); }, { disabled: !selected })));
      body.append(row(textField("Save current settings as…", presetName, (v) => { presetName = v; }),
        flatButton("Save", async () => { if (!presetName.trim()) return; await apply(presetName.trim()); selected = presetName.trim(); await refreshPresets(); }),
        flatButton("Import…", async () => {
          const native = a.engine.native;
          if (!native) { a.print('Use PAGEPRESET Import "file.archi" with archi-engine.'); return; }
          const path = await native.openFileDialog({ title: "Import named page setups", filters: [{ name: "Archi project", extensions: ["archi"] }] });
          if (path) { await a.tryCall("pagepresets.import", { path }); await refreshPresets(); }
        })));
      const targetList = h("details", {}, h("summary", { text: `Target sheets (${targets.size})` }));
      for (const item of info.layouts ?? []) targetList.append(toggle(item.name, targets.has(item.index), (on) => { if (on) targets.add(item.index); else targets.delete(item.index); targetList.querySelector("summary")!.textContent = `Target sheets (${targets.size})`; }));
      body.append(targetList, row(
        flatButton("Apply to Selected", async () => { await a.tryCall("pagepresets.apply", { name: selected, layouts: [...targets] }); await reload(); }, { disabled: !selected }),
        flatButton("Apply to All", async () => { await a.tryCall("pagepresets.apply", { name: selected, all: true }); await reload(); }, { disabled: !selected })), divider());
      body.append(
        picker(info.papers.map((p) => ({ value: p.name, title: p.label })), paper, (v) => { paper = v; }, { label: "Paper", width: 260 }),
        h("div", { class: "field-row" }, h("span", { text: "Orientation" }), segmented([{ value: false, title: "Landscape" }, { value: true, title: "Portrait" }], portrait, (v) => { portrait = v; }, 200)),
        divider());
      if (info.hasSection) {
        body.append(toggle("Customize section graphics on this sheet", sectionOn, (v) => { sectionOn = v; render(); }));
        if (sectionOn) {
          body.append(toggle("Shaded surfaces", section.shaded, (v) => { section.shaded = v; }));
          for (const [field, title] of [["color", "Section line colour"], ["cutFill", "Cut fill colour"]] as const) {
            const colour = section.lines[field] ?? { r: 0, g: 0, b: 0, a: 1 };
            const input = h("input", { type: "color", value: "#" + [colour.r, colour.g, colour.b].map((v) => Math.round(v * 255).toString(16).padStart(2, "0")).join("") });
            input.setAttribute("aria-label", title);
            input.addEventListener("input", () => { const v = parseInt(input.value.slice(1), 16); section.lines[field] = { r: (v >> 16) / 255, g: ((v >> 8) & 255) / 255, b: (v & 255) / 255, a: 1 }; });
            body.append(row(label(title), input));
          }
          for (const [field, title, value] of [["cutLineweight", "Cut weight (mm)", .5], ["projectionLineweight", "Projection (mm)", .25]] as const) {
            body.append(row(label(title), textField("mm", String(section.lines[field] ?? value), (v) => { const n = Number(v); if (Number.isFinite(n) && n > 0 && n <= 5) section.lines[field] = n; })));
          }
          body.append(note("Section viewports on this sheet only. Choose Color below to preserve colours; Preview shows the final output."));
        }
      }
    }
    body.append(picker(info.colorModes.map((m) => ({ value: m, title: m })), setup.colorMode, (v) => { setup.colorMode = v; }, { label: "Plot style", width: 160 }));
    if (info.tables.length) body.append(picker([{ value: "", title: "None" }, ...info.tables.map((t) => ({ value: t, title: t }))], setup.plotStyleTable ?? "", (v) => { setup.plotStyleTable = v || undefined; }, { label: "Plot style table", width: 180 }));
    if (info.namedTables.length) body.append(picker([{ value: "", title: "None (colour-dependent)" }, ...info.namedTables.map((t) => ({ value: t, title: t }))], setup.namedStyleTable ?? "", (v) => { setup.namedStyleTable = v || undefined; }, { label: "Named plot styles", width: 200 }));
    body.append(row(label("Lineweights"), slider(0.25, 3, 0.25, setup.lineweightScale, (v) => { setup.lineweightScale = v; lw.textContent = `×${v.toFixed(2)}`; }, 220), lw));
    body.append(toggle("Plot stamp", setup.plotStamp, (v) => { setup.plotStamp = v; render(); }));
    if (setup.plotStamp) {
      const f = textField(info.stampTemplate, setup.stampText ?? "", (v) => { setup.stampText = v || undefined; });
      f.style.width = "100%";
      body.append(f, note("Fields: " + info.stampFields.join(" ")));
    }
    if (!info.isSheet) {
      body.append(divider(),
        picker(info.papers.map((p) => ({ value: p.name, title: p.modelLabel })), setup.modelPaper, (v) => { setup.modelPaper = v; }, { label: "Paper", width: 220 }),
        h("div", { class: "field-row" }, h("span", { text: "Orientation" }), segmented([{ value: false, title: "Landscape" }, { value: true, title: "Portrait" }], setup.modelPortrait, (v) => { setup.modelPortrait = v; }, 200)),
        picker(info.plotAreas.map((p) => ({ value: p, title: p })), setup.plotArea, (v) => {
          setup.plotArea = v;
          const d = pageSetupHooks.displayBox();
          if ((v === "Display" || (v === "Window" && !validWindow(setup.plotWindow))) && d) setup.plotWindow = d;
          render();
        }, { label: "Plot area", width: 140 }));
      if (setup.plotArea === "Window") body.append(note("Window: PLOTAREA Window picks the corners in the drawing."));
      body.append(toggle("Exact fit (not rounded to a standard scale)", setup.exactFit, (v) => { setup.exactFit = v; }, { disabled: scaleText !== "Fit" }),
        picker(info.scales, scaleText, (v) => { scaleText = v; setup.modelScale = v === "Fit" ? undefined : Number(v.slice(2)); render(); }, { label: "Scale", width: 140 }));
    }
  };
  render();
  const apply = async (saveName?: string) => {
    const params: any = { setup: { ...setup, stampText: setup.stampText ?? null, plotStyleTable: setup.plotStyleTable ?? null, namedStyleTable: setup.namedStyleTable ?? null, modelScale: setup.modelScale ?? null }, scaleText };
    if (info.isSheet) { params.layout = info.layout; params.paper = paper; params.portrait = portrait; params.sectionStyle = sectionOn ? section : null; if (saveName) { params.presetName = saveName; params.presetOnly = true; } if (presetSource) params.presetSource = presetSource; }
    await a.tryCall("pagesetup.set", params);
    await a.refresh(["document", "drawing"]);
  };
  const handle = sheet({
    title: info.title, content: body,
    footerLeft: flatButton("Preview…", async () => { await apply(); handle.close(); await a.runCommand("PREVIEW"); }),
    onCancel: () => {}, onOK: () => apply(),
  });
}
function validWindow(w?: number[]) { return !!w && w.length === 4 && w[2] - w[0] > 0 && w[3] - w[1] > 0; }
