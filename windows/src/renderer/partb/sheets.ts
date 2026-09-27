// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Sheet Set Manager (the Sheets panel, SheetSetManager.swift: numbering, order, duplicate, delete, rename, revisions,
// sheet index, view titles) and the Title Block dialog (TitleBlockSheet in PlotExtras.swift: project fields for all
// sheets, logo, custom fields, this sheet's fields with automatic values, "All" for revision / date / scale).
import type { App } from "../app";
import { h, clear, button, iconButton, field, numberField, checkbox, menuButton, spacer, header, Sheet, showMenu, help, ico, load, store } from "./ui";
import * as N from "./native";

interface SheetInfo { index: number; name: string; number: string; title: string; paper: { name: string; width: number; height: number }; viewports: number; revisions: { code: string; date: string; description: string; by: string }[]; titleBlock: Record<string, string>; viewTitles: boolean; hasIndex: boolean }
interface SheetSetData { sheets: SheetInfo[]; papers: { name: string; width: number; height: number }[]; author: string; current: string }

/** Current sheet index (0-based) from the window's active layout (0 = Model in the Windows shell). */
export function currentSheet(app: App, count: number) { return Math.min(Math.max((app.activeLayout || 1) - 1, 0), Math.max(count - 1, 0)); }
export function openSheet(app: App, i: number, show = false) {
  app.activeLayout = i + 1;
  const name = app.info?.layouts?.[i];
  if (name) app.tryCall("panel.set", { panel: "sheets", key: "current", value: name });
  if (show) app.setUI("mode", "Sheet"); else app.emit("ui");
}

let editingName: number | null = null;
const form = { prefix: load<string>("sheets.prefix", "A-"), start: load<number>("sheets.start", 101), revDescription: "", revBy: "" };

export async function renderSheetSetPanel(app: App, body: HTMLElement) {
  const data: SheetSetData | null = await app.tryCall("sheetset.get");
  clear(body);
  if (!data) { body.append(h("div", { class: "pempty", text: "Sheets are not available." })); return; }
  const sheets = data.sheets;
  const cur = currentSheet(app, sheets.length);
  const redraw = () => renderSheetSetPanel(app, body);
  const op = async (params: any) => {
    const r = await app.tryCall("sheetset.edit", params);
    await app.refresh(["document"]);
    if (r && typeof r.index === "number" && ["new", "duplicate", "move", "delete"].includes(params.op)) openSheet(app, r.index);
    redraw();
    return r;
  };
  const bar = h("div", { class: "pb-row", style: { padding: "8px", gap: "4px" } },
    menuButton("New", "plus", () => data.papers.map((p) => ({ title: `${p.name} landscape`, action: () => op({ op: "new", paper: p.name }) }))),
    iconButton("plus.square.on.square", "Duplicate the selected sheet", () => op({ op: "duplicate", index: cur }), { disabled: !sheets.length }),
    iconButton("arrow.up", "Move the sheet up in the set", () => op({ op: "move", index: cur, to: cur - 1 }), { disabled: cur === 0 || !sheets.length }),
    iconButton("arrow.down", "Move the sheet down in the set", () => op({ op: "move", index: cur, to: cur + 1 }), { disabled: cur >= sheets.length - 1 }),
    spacer(),
    iconButton("trash", "Delete the selected sheet", () => op({ op: "delete", index: cur }), { disabled: sheets.length < 2 }));
  const listEl = h("div", { class: "pb-scroll", style: { minHeight: "120px", flex: "1" } });
  sheets.forEach((s, i) => {
    const sel = i === cur;
    const nameEl: HTMLElement = editingName === i
      ? field({ value: s.name, flex: true, onCommit: async (v) => { editingName = null; const n = v.trim(); if (n && n !== s.name) await op({ op: "rename", index: i, name: n }); else redraw(); } })
      : h("span", { style: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }, text: s.name });
    const row = h("div", { class: "pb-list-row" + (sel ? " sel" : ""), style: { height: "24px" }, "data-sheet": String(i) },
      h("span", { class: sel ? "" : "pb-accent", style: { width: "58px", flex: "none", font: "600 11px var(--mono)" }, text: s.number }),
      nameEl, spacer(),
      h("span", { class: "pb-small" + (sel ? "" : " pb-dim"), text: `${s.viewports} vp · ${s.paper.name}` }),
      h("span", { class: "pb-small" + (sel ? "" : " pb-dim"), style: { width: "22px", textAlign: "center" }, text: s.revisions[s.revisions.length - 1]?.code ?? "—" }));
    help(row, "Double-click to open the sheet");
    row.addEventListener("click", () => { if (editingName !== i) editingName = null; openSheet(app, i); redraw(); });
    row.addEventListener("dblclick", () => openSheet(app, i, true));
    row.addEventListener("contextmenu", (e) => {
      e.preventDefault();
      showMenu([{ title: "Open", action: () => openSheet(app, i, true) },
        { title: "Rename", action: () => { editingName = i; redraw(); } },
        { title: "Title Block…", action: () => { openSheet(app, i, true); showTitleBlock(app, i); } },
        { title: "Duplicate", action: () => { openSheet(app, i); op({ op: "duplicate", index: i }); } },
        { separator: true },
        { title: "Delete", disabled: sheets.length < 2, action: () => { openSheet(app, i); op({ op: "delete", index: i }); } }], { x: e.clientX, y: e.clientY });
    });
    listEl.append(row);
  });
  body.append(bar, h("div", { class: "pb-hsep" }), listEl);
  if (!sheets.length) return;
  const s = sheets[cur];
  const revs = s.revisions;
  const details = h("div", { class: "pb-col pb-scroll", style: { padding: "8px", gap: "8px", maxHeight: "280px" } },
    h("div", { class: "pb-header", text: "NUMBERING" }),
    h("div", { class: "pb-row", style: { gap: "4px" } },
      field({ value: form.prefix, placeholder: "Prefix", width: 50, onInput: (v) => { form.prefix = v; store("sheets.prefix", v); } }),
      numberField(form.start, (v) => { form.start = Math.round(v); store("sheets.start", form.start); }, { width: 56, decimals: 0, placeholder: "Start" }),
      button("Renumber All", { compact: true, onClick: () => op({ op: "renumber", prefix: form.prefix, start: form.start }) })),
    h("div", { class: "pb-row", style: { gap: "4px" } },
      button("Sheet Index Here", { compact: true, help: "Place or refresh the sheet list table on this sheet (SHEETINDEX)", onClick: () => op({ op: "index", index: cur }) }),
      button("View Titles", { compact: true, disabled: !s.viewports, help: "Editable view titles under every viewport (number, title, scale)", onClick: () => op({ op: "viewTitles", index: cur }) })),
    h("div", { class: "pb-hsep" }),
    h("div", { class: "pb-header", text: `REVISIONS — ${s.name}` }));
  if (!revs.length) details.append(h("div", { class: "pb-small pb-faint", text: "No revisions yet." }));
  revs.forEach((r, k) => details.append(h("div", { class: "pb-row", style: { gap: "6px" } },
    h("span", { class: "pb-accent", style: { width: "26px", font: "600 11px var(--mono)" }, text: r.code }),
    h("span", { class: "pb-small pb-dim", text: r.date }),
    h("span", { style: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }, text: r.description }), spacer(),
    h("span", { class: "pb-small pb-dim", text: r.by }),
    iconButton("minus.circle", "Delete this revision", () => op({ op: "deleteRevision", index: cur, revision: k })))));
  const desc = field({ value: form.revDescription, placeholder: "Description", flex: true, onInput: (v) => { form.revDescription = v; } });
  const by = field({ value: form.revBy, placeholder: "By", width: 44, onInput: (v) => { form.revBy = v; } });
  details.append(h("div", { class: "pb-row", style: { gap: "4px" } }, desc, by,
    button("Add", { compact: true, onClick: async () => {
      const d = form.revDescription.trim();
      if (!d) { desc.focus(); return; }
      form.revDescription = "";
      await op({ op: "addRevision", index: cur, description: d, by: form.revBy || data.author });
    } })),
    h("div", { class: "pb-small pb-faint", text: "Revisions appear in a table above the title block and set its Revision field." }));
  body.append(h("div", { class: "pb-hsep" }), details);
}

// ---- Title block (TITLEBLOCK) ----

const SHEET_KEYS: [string, string][] = [["sheetName", "Sheet title"], ["sheetNumber", "Sheet number"], ["scale", "Scale"], ["date", "Date"], ["revision", "Revision"]];
const PROJECT_OVERRIDE_KEYS: [string, string][] = [["project", "Project"], ["client", "Client"], ["author", "Drawn by"], ["number", "Project no."]];

export async function showTitleBlock(app: App, layout?: number) {
  const count = app.info?.layouts?.length ?? 0;
  if (!count) { app.print("The drawing has no sheets."); return; }
  const li = layout ?? currentSheet(app, count);
  const d = await app.tryCall("titleblock.get", { layout: li });
  if (!d) return;
  const info: Record<string, string> = { name: d.info?.name ?? "", number: d.info?.number ?? "", client: d.info?.client ?? "", address: d.info?.address ?? "", author: d.info?.author ?? "" };
  const fields: Record<string, string> = { ...(d.fields ?? {}) };
  const projectCustom: Record<string, string> = { ...(d.projectCustom ?? {}) };
  const sheetCustom: Record<string, string> = { ...(d.sheetCustom ?? {}) };
  const applyToAll = new Set<string>();
  let logo: string = d.logo ?? "";
  let newLabel = "";
  const sheet = new Sheet(610);
  sheet.el.dataset.sheet = "titleBlock";
  const left = h("div", { class: "pb-col", style: { width: "250px", gap: "7px" } });
  const right = h("div", { class: "pb-col", style: { width: "300px", gap: "7px" } });
  const f = (label: string, value: string, set: (v: string) => void, placeholder = "") => h("div", { class: "pb-row" }, h("span", { class: "pb-dim", style: { width: "84px", flex: "none" }, text: label }), field({ value, placeholder, flex: true, onInput: set }));
  const renderLeft = () => {
    clear(left);
    left.append(header("Project (all sheets)"),
      f("Project name", info.name, (v) => { info.name = v; }), f("Project no.", info.number, (v) => { info.number = v; }), f("Client", info.client, (v) => { info.client = v; }),
      f("Address", info.address, (v) => { info.address = v; }), f("Drawn by", info.author, (v) => { info.author = v; }),
      h("div", { class: "pb-small pb-dim", text: "Every title block shows these unless a sheet overrides them." }),
      h("div", { class: "pb-row" }, h("span", { class: "pb-dim", style: { width: "84px", flex: "none" }, text: "Logo" }), h("span", { style: { flex: "1", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }, text: logo ? N.basename(logo) : "None" }),
        button("Choose…", { compact: true, onClick: async () => { const p = await N.openFile(app, "Choose a logo", [{ name: "Images", extensions: ["png", "jpg", "jpeg", "svg", "tif", "tiff", "bmp"] }]); if (p) { logo = p; renderLeft(); } } }),
        logo ? button("Remove", { compact: true, onClick: () => { logo = ""; renderLeft(); } }) : null),
      h("div", { class: "pb-header", style: { paddingTop: "6px" }, text: "Custom fields" }));
    for (const k of [...new Set([...Object.keys(projectCustom), ...Object.keys(sheetCustom)])].sort()) {
      left.append(f(k.charAt(0) + k.slice(1).toLowerCase(), projectCustom[k] ?? "", (v) => { projectCustom[k] = v; }, "project value"),
        f("  this sheet", sheetCustom[k] ?? "", (v) => { sheetCustom[k] = v; }, "same as project"));
    }
    const nl = field({ value: newLabel, placeholder: "New field label", flex: true, onInput: (v) => { newLabel = v; } });
    left.append(h("div", { class: "pb-row" }, nl, button("Add", { onClick: () => { const l = newLabel.trim().toUpperCase(); if (l) { projectCustom[l] = projectCustom[l] ?? ""; newLabel = ""; renderLeft(); } } })));
  };
  renderLeft();
  right.append(header("This sheet"));
  for (const [k, label] of [...SHEET_KEYS, ...PROJECT_OVERRIDE_KEYS]) {
    const r = f(label, fields[k] ?? "", (v) => { fields[k] = v; }, d.defaults?.[k] ?? "");
    if (["revision", "date", "scale"].includes(k)) r.append(checkbox("All", false, (v) => { if (v) applyToAll.add(k); else applyToAll.delete(k); }, "Apply this value to every sheet"));
    right.append(r);
  }
  right.append(h("div", { class: "pb-small pb-dim", text: "Leave a field empty to use the automatic value shown in grey." }));
  const ok = async () => {
    await app.tryCall("titleblock.apply", { layout: li, info, logo, projectCustom, sheetCustom, fields, applyToAll: [...applyToAll] });
    sheet.close();
    await app.refresh(["document"]);
  };
  sheet.body.append(h("div", { class: "pb-sheet-head" }, h("span", { text: `Title Block — ${d.name ?? ""}` })), h("div", { class: "pb-hsep" }),
    h("div", { class: "pb-row pb-scroll", style: { alignItems: "flex-start", gap: "20px", padding: "14px", maxHeight: "560px" } }, left, right),
    h("div", { class: "pb-hsep" }),
    h("div", { class: "pb-sheet-foot" }, button("Cancel", { onClick: () => sheet.close() }), button("OK", { prominent: true, onClick: ok })));
  sheet.overlay.addEventListener("keydown", (e) => { if (e.key === "Enter" && (e.target as HTMLElement).tagName !== "TEXTAREA") { e.preventDefault(); ok(); } });
  void ico;
}
