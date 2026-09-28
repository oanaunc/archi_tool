// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Plotting (ArchiApp/PlotExtras.swift PlotPreviewWindow / PlotPreviewView / PageSetupForm, Plotter.swift
// printDrawing, PrintSetup.swift PrintSetupWindow / PrintSetupView): the Plot dialog with a live preview — the engine
// writes the PDF (plot.preview) and returns the same pages as SVG, so Save PDF… copies exactly the previewed file and
// Print… prints exactly the previewed pages through Windows printing (src/main/output.ts) — and Print Setup with the
// printer, paper, roll and custom sizes, scaling and copies (remembered between prints).
import type { App } from "../app";
import { std } from "../standards/native";
import { h, clear } from "../dom";
import { toolWindow, picker, segmented, slider, toggle, textField, flatButton, note, label, row, divider, stepper, Option } from "../dialogs/ui";
import { out, saveDialog, docName } from "./native";

interface Setup {
  colorMode: string; lineweightScale: number; plotStamp: boolean; stampText?: string; modelPaper: string; modelPortrait: boolean; modelScale?: number;
  plotStyleTable?: string; namedStyleTable?: string; plotArea: string; plotWindow?: number[]; exactFit: boolean;
}
interface PageSetupInfo {
  isSheet: boolean; layout: number | null; title: string; paper?: string; portrait?: boolean;
  papers: { name: string; width: number; height: number; label: string; modelLabel: string }[];
  setup: Setup; scaleText: string; colorModes: string[]; plotAreas: string[]; tables: string[]; namedTables: string[];
  scales: Option[]; stampTemplate: string; stampFields: string[];
}
export interface PlotPage { name: string; width: number; height: number; svg?: string; svgPath?: string }
export interface PreviewResult { pdf: string; bytes: number; pageCount: number; pages: PlotPage[]; title: string; ratio: number | null; status: string }

export const hooks: { displayBox: () => number[] | null } = { displayBox: () => null };

/** The target shown by default: the active sheet in the Sheet view, else the current level's model space. */
export function currentTarget(app: App): string {
  return app.mode === "Sheet" && app.activeLayout > 0 ? `sheet:${app.activeLayout - 1}` : "model";
}

/** PageSetupForm: plot style, tables, lineweights, stamp; for model space paper, orientation, area, fit and scale. */
export function pageSetupForm(info: PageSetupInfo, setup: Setup, state: { scaleText: string }, showModel: boolean, changed: () => void): HTMLElement {
  const body = h("div", { class: "dcol plot-form" });
  const lw = label(`×${setup.lineweightScale.toFixed(2)}`, { mono: true, width: 44 });
  lw.style.textAlign = "right";
  const render = () => {
    clear(body);
    body.append(picker(info.colorModes.map((m) => ({ value: m, title: m })), setup.colorMode, (v) => { setup.colorMode = v; changed(); }, { label: "Plot style", width: 150 }));
    if (info.tables.length) body.append(picker([{ value: "", title: "None" }, ...info.tables.map((t) => ({ value: t, title: t }))], setup.plotStyleTable ?? "", (v) => { setup.plotStyleTable = v || undefined; changed(); }, { label: "Plot style table", width: 150 }));
    if (info.namedTables.length) body.append(picker([{ value: "", title: "None (colour-dependent)" }, ...info.namedTables.map((t) => ({ value: t, title: t }))], setup.namedStyleTable ?? "", (v) => { setup.namedStyleTable = v || undefined; changed(); }, { label: "Named plot styles", width: 140 }));
    body.append(row(label("Lineweights"), slider(0.25, 3, 0.25, setup.lineweightScale, (v) => { setup.lineweightScale = v; lw.textContent = `×${v.toFixed(2)}`; changed(); }, 150), lw));
    body.append(toggle("Plot stamp", setup.plotStamp, (v) => { setup.plotStamp = v; render(); changed(); }));
    if (setup.plotStamp) {
      const f = textField(info.stampTemplate, setup.stampText ?? "", (v) => { setup.stampText = v || undefined; changed(); });
      f.style.width = "100%";
      body.append(f, note("Fields: " + info.stampFields.join(" ")));
    }
    if (showModel) {
      body.append(divider(),
        picker(info.papers.map((p) => ({ value: p.name, title: p.modelLabel })), setup.modelPaper, (v) => { setup.modelPaper = v; changed(); }, { label: "Paper", width: 180 }),
        h("div", { class: "field-row" }, h("span", { text: "Orientation" }), segmented([{ value: false, title: "Landscape" }, { value: true, title: "Portrait" }], setup.modelPortrait, (v) => { setup.modelPortrait = v; changed(); }, 180)),
        picker(info.plotAreas.map((p) => ({ value: p, title: p })), setup.plotArea, (v) => {
          setup.plotArea = v;
          const d = hooks.displayBox();
          if ((v === "Display" || (v === "Window" && !validWindow(setup.plotWindow))) && d) setup.plotWindow = d;
          render(); changed();
        }, { label: "Plot area", width: 120 }));
      if (setup.plotArea === "Window") body.append(note("Window: PLOTAREA Window picks the corners in the drawing."));
      body.append(toggle("Exact fit (not rounded to a standard scale)", setup.exactFit, (v) => { setup.exactFit = v; changed(); }, { disabled: state.scaleText !== "Fit" }),
        picker(info.scales, state.scaleText, (v) => { state.scaleText = v; setup.modelScale = v === "Fit" ? undefined : Number(v.slice(2)); render(); changed(); }, { label: "Scale", width: 130 }));
    }
  };
  render();
  return body;
}
function validWindow(w?: number[]) { return !!w && w.length === 4 && w[2] - w[0] > 0 && w[3] - w[1] > 0; }
function setupParams(setup: Setup) {
  return { ...setup, stampText: setup.stampText ?? null, plotStyleTable: setup.plotStyleTable ?? null, namedStyleTable: setup.namedStyleTable ?? null, modelScale: setup.modelScale ?? null };
}

/** Paper pages (SVG) on the PDFView's grey, scaled to the width, one under the other. */
export function pageView(pages: PlotPage[]): HTMLElement {
  const wrap = h("div", { class: "plot-pages" });
  for (const p of pages) {
    const page = h("div", { class: "plot-page", "data-name": p.name });
    page.style.aspectRatio = `${p.width} / ${p.height}`;
    const n = (window as any).archi;
    if (p.svgPath && n?.fileUrl) page.append(h("img", { src: n.fileUrl(p.svgPath), alt: p.name, draggable: false }));
    else if (p.svg) { page.innerHTML = p.svg; const s = page.querySelector("svg"); if (s) { s.setAttribute("width", "100%"); s.setAttribute("height", "100%"); } }
    wrap.append(page);
  }
  return wrap;
}

// ---- Plot / Preview (PREVIEW, PLOT dialog) ----

export async function openPlotPreview(app: App) {
  const info = await app.tryCall("plot.info");
  if (!info) { app.print("Plotting needs archi-engine."); return; }
  const title = `Plot Preview — ${docName(app)}`;
  toolWindow("plotPreview", title, 1080, 720, (body, win) => {
    win.el.classList.add("plot-window");
    let what: string = info.default ?? currentTarget(app);
    let psInfo: PageSetupInfo | null = null;
    let setup: Setup | null = null;
    const state = { scaleText: "Fit" };
    let preview: PreviewResult | null = null;
    let error = "";
    let seq = 0, timer = 0;
    const side = h("div", { class: "plot-side" });
    const viewer = h("div", { class: "plot-viewer" });
    const status = h("div", { class: "dnote plot-count" });
    const errEl = h("div", { class: "dnote danger" });
    const saveBtn = flatButton("Save PDF…", () => void savePDF(), { disabled: true });
    const printBtn = flatButton("Print…", () => void print(), { prominent: true, disabled: true });
    const layoutOf = () => (what.startsWith("sheet:") ? Number(what.slice(6)) : null);
    body.append(side, h("div", { class: "vsep" }), viewer);
    async function loadSetup() {
      const li = layoutOf();
      psInfo = await app.tryCall("pagesetup.get", what === "all" || li === null ? {} : { layout: li });
      setup = psInfo ? { ...psInfo.setup } : null;
      state.scaleText = psInfo?.scaleText ?? "Fit";
      renderSide();
      regenerate(0);
    }
    function renderSide() {
      clear(side);
      side.append(h("div", { class: "plot-cap", text: "PLOT" }),
        picker((info.what as Option[]), what, (v) => { what = v; void loadSetup(); }, { label: "What", width: 220 }));
      if (psInfo && setup) side.append(pageSetupForm(psInfo, setup, state, what === "model", () => regenerate()));
      if (what !== "model") side.append(note(info.sheetNote ?? "Sheets plot at 1:1 on their own paper; change paper and viewports in the Sheet view."));
      side.append(row(flatButton("Save as Default", () => void saveDefault(), { compact: true, disabled: what === "all", help: "Store these settings in the drawing's page setup" })));
      side.append(h("div", { class: "spacer" }), errEl, status,
        h("div", { class: "drow plot-buttons" }, flatButton("Close", () => win.close()), h("span", { class: "spacer" }), saveBtn, printBtn));
    }
    function regenerate(delay = 180) {
      clearTimeout(timer);
      timer = window.setTimeout(async () => {
        const my = ++seq;
        const params: any = { what, svg: true, svgFiles: !!app.engine.native };
        if (what !== "all" && setup) { params.setup = setupParams(setup); params.scaleText = state.scaleText; }
        try {
          const r: PreviewResult = await app.engine.call("plot.preview", params);
          if (my !== seq) return;
          preview = r; error = "";
          clear(viewer); viewer.append(pageView(r.pages));
          status.textContent = `${r.pageCount} page(s)`;
        } catch (e: any) { if (my !== seq) return; error = e?.message ?? String(e); preview = null; }
        errEl.textContent = error;
        saveBtn.disabled = printBtn.disabled = !preview;
      }, delay);
    }
    async function saveDefault() {
      if (!setup || what === "all") return;
      const li = layoutOf();
      await app.tryCall("pagesetup.set", { ...(li === null ? {} : { layout: li }), setup: setupParams(setup), scaleText: state.scaleText });
      await app.refresh(["document"]);
    }
    async function savePDF() {
      if (!preview) return;
      const li = layoutOf();
      const name = what === "model" ? docName(app) : what === "all" ? `${docName(app)} — sheets` : (app.info?.layouts[li ?? 0] ?? "Sheet");
      const path = await saveDialog(app, "Save PDF", name + ".pdf", [{ name: "PDF", extensions: ["pdf"] }]);
      if (!path) return;
      try { await app.engine.call("plot.pdf", { what, path, fromPreview: true, ...(what !== "all" && setup ? { setup: setupParams(setup), scaleText: state.scaleText } : {}) }); }
      catch (e: any) { errEl.textContent = e?.message ?? String(e); }
    }
    async function print() {
      if (!preview) return;
      await printPages(app, preview.pages, { title: app.info?.title ?? preview.title, showDialog: true, scaling: "fit" });
    }
    void loadSetup();
  });
}

// ---- Printing ----

export interface PrintOptions {
  printer: string; paper: string; tray: string; mediaType: string; scaling: "fit" | "actual" | "custom"; percent: number; copies: number;
  showSystemDialog: boolean; sizeMode: "printer" | "drawing" | "roll"; rollWidth: number;
}
const PRINT_KEY = "archi.print.options";
export function loadPrintOptions(): PrintOptions {
  const d: PrintOptions = { printer: "", paper: "", tray: "", mediaType: "", scaling: "fit", percent: 100, copies: 1, showSystemDialog: false, sizeMode: "printer", rollWidth: 914 };
  try { return { ...d, ...JSON.parse(localStorage.getItem(PRINT_KEY) ?? "{}") }; } catch { return d; }
}
export function savePrintOptions(o: PrintOptions) { try { localStorage.setItem(PRINT_KEY, JSON.stringify(o)); } catch { /* private mode */ } }
const SCALING: Option<PrintOptions["scaling"]>[] = [{ value: "fit", title: "Fit to Paper" }, { value: "actual", title: "Actual Size (1:1 paper)" }, { value: "custom", title: "Custom %" }];

/** Prints plotted pages (native: Windows printing; browser: the page's print dialog). Remembered for tests. */
export async function printPages(app: App, pages: PlotPage[], o: { title: string; showDialog: boolean; scaling: PrintOptions["scaling"]; percent?: number; printer?: string; paper?: string; copies?: number; tray?: string; mediaType?: string }): Promise<boolean> {
  const job = { title: o.title, pages: pages.map((p) => ({ svg: p.svg, svgPath: p.svgPath, width: p.width, height: p.height })), printer: o.printer, paper: o.paper, scaling: o.scaling, percent: o.percent, copies: o.copies, showDialog: o.showDialog, tray: o.tray || undefined, mediaType: o.mediaType || undefined };
  (window as any).archiLastPrintJob = job;
  const n = out();
  if (n) {
    const r = await n.print(job);
    if (!r.ok && r.error && r.error !== "cancelled") app.print(`Plot failed: ${r.error}`);
    return r.ok;
  }
  // Browser: print the pages from a hidden frame.
  const f = h("iframe", { style: { position: "fixed", width: "0", height: "0", border: "0", visibility: "hidden" } }) as HTMLIFrameElement;
  document.body.append(f);
  const d = f.contentDocument!;
  d.open();
  d.write(`<!doctype html><title>${o.title}</title><style>@page{margin:0}body{margin:0}.p{page-break-after:always}svg{width:100%;height:auto}</style>${pages.map((p) => `<div class="p">${p.svg ?? ""}</div>`).join("")}`);
  d.close();
  if (!(window as any).archiNoPrintDialog) f.contentWindow?.print();
  setTimeout(() => f.remove(), 1000);
  return true;
}

/** PLOT without a file (and Ctrl+P): the active sheet or the current level with the print dialog (Plotter.printDrawing). */
export async function printDrawing(app: App) {
  try {
    const r: PreviewResult = await app.engine.call("plot.preview", { what: currentTarget(app), svg: true, svgFiles: !!app.engine.native });
    await printPages(app, r.pages, { title: app.info?.title ?? r.title, showDialog: true, scaling: "fit" });
  } catch (e: any) { app.print(`Plot failed: ${e?.message ?? e}`); }
}

// ---- Print Setup (PRINTSETUP) ----

export async function openPrintSetup(app: App) {
  toolWindow("printSetup", "Print", 420, 420, (body) => {
    const o = loadPrintOptions();
    let printers: { name: string; displayName: string; isDefault: boolean }[] = [];
    // Input trays and media types of the printer (Print Schema capabilities of the Windows print queue).
    let caps: { trays: { value: string; title: string }[]; media: { value: string; title: string }[] } = { trays: [], media: [] };
    const loadCaps = () => {
      const s = std();
      if (!s) return;
      const name = o.printer || (printers.find((p) => p.isDefault)?.name ?? "");
      void s.printerCaps(name).then((c) => { caps = c; if (!caps.trays.some((t) => t.value === o.tray)) o.tray = ""; if (!caps.media.some((m) => m.value === o.mediaType)) o.mediaType = ""; render(); }).catch(() => {});
    };
    const form = h("div", { class: "dcol print-form" });
    body.append(form);
    const papers = ["A4", "A3", "A2", "A1", "A0", "Letter", "Legal", "Tabloid"];
    const render = () => {
      clear(form);
      form.append(
        picker([{ value: "", title: "Default" }, ...printers.map((p) => ({ value: p.name, title: p.displayName }))], o.printer, (v) => { o.printer = v; o.tray = ""; o.paper = ""; o.mediaType = ""; caps = { trays: [], media: [] }; render(); loadCaps(); }, { label: "Printer", width: 260 }),
        picker([{ value: "", title: "Printer default" }, ...papers.map((p) => ({ value: p, title: p }))], o.paper, (v) => { o.paper = v; }, { label: "Paper", width: 260 }),
        picker([{ value: "", title: "Auto select" }, ...caps.trays], o.tray, (v) => { o.tray = v; }, { label: "Tray", width: 260, disabled: !caps.trays.length }),
        ...(caps.media.length ? [picker([{ value: "", title: "Printer default" }, ...caps.media], o.mediaType, (v) => { o.mediaType = v; }, { label: "Media", width: 260 })] : []),
        picker<PrintOptions["sizeMode"]>([{ value: "printer", title: "Printer paper" }, { value: "drawing", title: "Match drawing (custom size)" }, { value: "roll", title: "Roll paper" }], o.sizeMode, (v) => { o.sizeMode = v; render(); }, { label: "Paper size", width: 220 }));
      if (o.sizeMode === "roll") {
        const f = textField("mm", String(o.rollWidth), (v) => { const n = Number(v); if (n > 0) o.rollWidth = Math.max(100, n); }, { width: 70 });
        const common = flatButton("Common", () => {
          const items = [610, 841, 914, 1067, 1118, 1524];
          const m = h("div", { class: "menu" });
          const r = common.getBoundingClientRect();
          Object.assign(m.style, { left: r.left + "px", top: r.bottom + 2 + "px" });
          for (const w of items) { const mi = h("div", { class: "mi", text: `${w} mm` }); mi.addEventListener("click", () => { o.rollWidth = w; m.remove(); render(); }); m.append(mi); }
          document.body.append(m);
          setTimeout(() => addEventListener("mousedown", function x(ev) { if (!m.contains(ev.target as Node)) { m.remove(); removeEventListener("mousedown", x); } }), 0);
        }, { compact: true });
        form.append(row(label("Roll width"), f, label("mm", { dim: true }), h("span", { class: "spacer" }), common));
      }
      if (o.sizeMode === "printer") form.append(picker(SCALING, o.scaling, (v) => { o.scaling = v; render(); }, { label: "Scale", width: 220 }));
      if (o.scaling === "custom" && o.sizeMode === "printer") {
        const pl = label(`${o.percent} %`, { mono: true, width: 56 });
        form.append(row(slider(10, 400, 5, o.percent, (v) => { o.percent = v; pl.textContent = `${v} %`; }, 220), pl));
      }
      form.append(stepper((v) => `Copies: ${v}`, o.copies, 1, 99, (v) => { o.copies = v; }),
        toggle("Show the system print dialog", o.showSystemDialog, (v) => { o.showSystemDialog = v; }),
        note(app.mode === "Sheet" ? "Prints the active sheet." : "Prints the drawing (current level). Sheets print at their plot scale with Actual Size."),
        h("div", { class: "drow", style: { width: "100%" } }, h("span", { class: "spacer" }), flatButton("Print", () => { savePrintOptions(o); void printWith(app, o); })));
    };
    render();
    const n = out();
    if (n) void n.printers().then((list) => { printers = list; render(); loadCaps(); }).catch(() => {});
  });
}

export async function printWith(app: App, o: PrintOptions) {
  let r: PreviewResult;
  try { r = await app.engine.call("plot.preview", { what: currentTarget(app), svg: true, svgFiles: !!app.engine.native }); }
  catch (e: any) { app.print(`Print failed: ${e?.message ?? e}`); return; }
  const paper = o.sizeMode === "drawing" ? "drawing" : o.sizeMode === "roll" ? `roll:${o.rollWidth}` : o.paper;
  const ok = await printPages(app, r.pages, { title: app.info?.title ?? r.title, showDialog: o.showSystemDialog, scaling: o.sizeMode === "printer" ? o.scaling : "actual", percent: o.percent, printer: o.printer, paper, copies: o.copies, tray: o.tray, mediaType: o.mediaType });
  if (!ok) return;
  const scale = o.scaling === "custom" ? `${o.percent}%` : SCALING.find((s) => s.value === o.scaling)!.title;
  app.print(`Sent ${app.info?.title ?? "the drawing"} to ${o.printer || "the default printer"}${o.tray ? `, tray ${o.tray.split("|").pop()}` : ""}, ${scale}, ${o.copies} cop${o.copies === 1 ? "y" : "ies"}.`);
}
