// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Publishing (ArchiApp/OutputDialogs.swift BatchPublishSheet, PlotExtras.swift Plotter.publish, AppCommandsNav SHEETSVG)
// and the plot style table editor (OutputDialogs.swift PlotStyleSheet): the sheets to publish with bookmarks and the
// sheet index, the save dialog of PUBLISH / BATCHPUBLISH All, the SVG folder of SHEETSVG, and the CTB pens per ACI colour.
import type { App } from "../app";
import { h, clear } from "../dom";
import { sheet, toggle, flatButton, note, label, picker, textField, slider } from "../dialogs/ui";
import { saveDialog, docName } from "./native";

/** Save dialog then plot.publish (PUBLISH with Enter, BATCHPUBLISH All with Enter). */
export async function publishWithDialog(app: App, o: { suggested?: string; bookmarks?: boolean; layouts?: number[]; index?: boolean }): Promise<any> {
  const path = await saveDialog(app, "Publish", o.suggested ?? `${docName(app)} — sheets.pdf`, [{ name: "PDF", extensions: ["pdf"] }]);
  if (!path) return null;
  try {
    return await app.engine.call("plot.publish", { path, bookmarks: o.bookmarks ?? true, ...(o.layouts ? { layouts: o.layouts } : {}), ...(o.index ? { index: true } : {}) });
  } catch (e: any) { app.print(e?.message ?? String(e)); return null; }
}

/** BatchPublishSheet: every sheet (number, name, paper · plot style), bookmarks, sheet index. */
export async function openBatchPublish(app: App) {
  const info = await app.tryCall("plot.info");
  if (!info) return;
  const sheets: { index: number; name: string; number: string; paper: string; style: string }[] = info.sheets ?? [];
  const chosen = new Set(sheets.map((s) => s.index));
  let bookmarks = true, index = false, status = "";
  const count = label("", { dim: true });
  const list = h("div", { class: "dlist bp-list" });
  const statusEl = note("", "accent");
  const title = h("div", { class: "drow", style: { width: "100%" } }, h("span", { text: "Batch Publish to PDF" }), h("span", { class: "spacer" }), count);
  const renderList = () => {
    clear(list);
    for (const s of sheets) {
      const t = toggle("", chosen.has(s.index), (v) => { if (v) chosen.add(s.index); else chosen.delete(s.index); update(); });
      list.append(h("div", { class: "li small bp-row" }, t, h("span", { class: "mono bp-num", text: s.number }), h("span", { text: s.name }), h("span", { class: "spacer" }), h("span", { class: "s", text: `${s.paper} · ${s.style}` })));
    }
  };
  const publishBtn = flatButton("Publish…", () => void publish(), { prominent: true });
  const update = () => { count.textContent = `${chosen.size} of ${sheets.length} sheets`; publishBtn.disabled = chosen.size === 0; };
  renderList(); update();
  const content = h("div", { class: "dcol", style: { width: "532px", gap: "10px" } }, list,
    toggle("PDF bookmarks (sheet number — name)", bookmarks, (v) => { bookmarks = v; }),
    toggle("Refresh the sheet index table on the first sheet", index, (v) => { index = v; }), statusEl);
  const all = flatButton("All", () => { sheets.forEach((s) => chosen.add(s.index)); renderList(); update(); }, { compact: true });
  const none = flatButton("None", () => { chosen.clear(); renderList(); update(); }, { compact: true });
  const handle = sheet({ title, content, width: 560, footerLeft: h("span", { class: "drow" }, all, none), footerButtons: [flatButton("Cancel", () => handle.close()), publishBtn], onOK: null, onCancel: null });
  async function publish() {
    const r = await publishWithDialog(app, { suggested: `${docName(app)} — sheets.pdf`, bookmarks, layouts: [...chosen].sort((a, b) => a - b), index });
    if (r) handle.close(); else { status = "Not published."; statusEl.textContent = status; }
  }
}

/** SHEETSVG with Enter: a folder (several sheets) or a file (one sheet). */
export async function sheetSVGWithDialog(app: App, p: { all: boolean; layout: number }) {
  const n = app.engine.native;
  let path: string | null;
  if (p.all) path = n?.chooseFolder ? await n.chooseFolder({ title: "Export" }) : "sheets";
  else path = await saveDialog(app, "Export SVG", `${app.info?.layouts[p.layout] ?? "Sheet"}.svg`, [{ name: "SVG", extensions: ["svg"] }]);
  if (!path) return;
  try { await app.engine.call("plot.sheetSVG", { all: p.all, layout: p.layout, path }); } catch (e: any) { app.print(e?.message ?? String(e)); }
}

// ---- Plot style tables (PLOTSTYLE Edit) ----

interface Pen { color: string | null; lineweight: number | null; screening: number }
interface Table { name: string; pens: Record<string, Pen | null>; builtIn?: boolean }

export async function openPlotStyles(app: App) {
  let data = await app.tryCall("plotstyle.list");
  if (!data) return;
  const tables = (): Table[] => data.tables;
  let table: Table = JSON.parse(JSON.stringify(tables().find((t) => t.name === data.current) ?? tables()[0]));
  let showAll = false;
  const aci: string[] = data.aci;
  const lineweights: number[] = data.lineweights;
  const rowsIdx = () => (showAll ? Array.from({ length: 256 }, (_, i) => i) : (data.rows as number[]));
  const grid = h("div", { class: "ps-grid" });
  const headPicker = h("span");
  const nameRow = h("div", { class: "drow ps-name" });
  const content = h("div", { class: "dcol", style: { width: "592px", gap: "8px" } }, nameRow, h("div", { class: "ps-scroll" }, grid));
  const renderHead = () => {
    clear(headPicker);
    const opts = tables().map((t) => ({ value: t.name, title: t.name }));
    if (!opts.some((o) => o.value === table.name)) opts.push({ value: table.name, title: table.name });
    headPicker.append(picker(opts, table.name, (v) => { const t = tables().find((x) => x.name === v); if (t) { table = JSON.parse(JSON.stringify(t)); render(); } }, { width: 200 }));
  };
  const uniqueName = (base: string) => {
    const stem = base.replace(/\.ctb$/i, "");
    let k = 2;
    while (tables().some((t) => t.name.toLowerCase() === `${stem} ${k}.ctb`.toLowerCase())) k++;
    return `${stem} ${k}.ctb`;
  };
  const render = () => {
    renderHead();
    clear(nameRow);
    nameRow.append(label("Name"), textField("", table.name, (v) => { table.name = v; }, { width: 220 }), h("span", { class: "spacer" }), toggle("All 255 colours", showAll, (v) => { showAll = v; render(); }));
    clear(grid);
    for (const t of ["Object colour", "Pen colour", "Lineweight", "Screening"]) grid.append(h("span", { class: "dnote", text: t }));
    for (const i of rowsIdx()) {
      const pen = table.pens[String(i)] ?? null;
      const upd = (f: (p: Pen) => void) => { const p: Pen = { color: null, lineweight: null, screening: 100, ...(table.pens[String(i)] ?? {}) }; f(p); table.pens[String(i)] = p; render(); };
      grid.append(h("span", { class: "drow ps-obj" }, i === 0 ? h("span", { class: "ps-pal", text: "◐" }) : h("span", { class: "ps-sw", style: { background: aci[i] } }), h("span", { text: i === 0 ? "Other" : `Color ${i}` })));
      const penCell = h("span", { class: "drow" }, toggle("Object", pen?.color == null, (on) => upd((p) => { p.color = on ? null : "#000000"; })));
      if (pen?.color != null) {
        const cw = h("input", { type: "color", class: "colorwell", value: pen.color }) as HTMLInputElement;
        cw.addEventListener("change", () => upd((p) => { p.color = cw.value; }));
        penCell.append(cw);
      }
      grid.append(penCell);
      grid.append(picker([{ value: -1, title: "Object" }, ...lineweights.map((w) => ({ value: w, title: `${w.toFixed(2)} mm` }))], pen?.lineweight ?? -1, (v) => upd((p) => { p.lineweight = v < 0 ? null : v; }), { width: 110 }));
      const pct = label(`${Math.round(pen?.screening ?? 100)}%`, { mono: true, width: 40 });
      pct.style.textAlign = "right";
      grid.append(h("span", { class: "drow" }, slider(0, 100, 1, pen?.screening ?? 100, (v) => { pct.textContent = `${v}%`; const p: Pen = { color: null, lineweight: null, screening: 100, ...(table.pens[String(i)] ?? {}) }; p.screening = v; table.pens[String(i)] = p; }, 90), pct));
    }
  };
  render();
  const title = h("div", { class: "drow", style: { width: "100%" } }, h("span", { text: "Plot Style Tables" }), h("span", { class: "spacer" }), headPicker,
    flatButton("New Copy", () => { table.name = uniqueName(table.name); render(); }, { compact: true }));
  const handle = sheet({
    title, content, width: 620,
    footerLeft: note("ACI colours map to pens; \"Other\" applies to true colours."),
    footerButtons: [flatButton("Close", () => handle.close()), flatButton("Save in Drawing", () => void save(), { prominent: true })],
    onOK: null, onCancel: null,
  });
  async function save() {
    const pens: Record<string, any> = {};
    for (const [k, p] of Object.entries(table.pens)) if (p) pens[k] = { color: p.color, lineweight: p.lineweight, screening: p.screening };
    const r = await app.tryCall("plotstyle.save", { table: { name: table.name, pens } });
    if (r) { data = r.list; table.name = r.name; render(); await app.refresh(["document"]); }
  }
}
