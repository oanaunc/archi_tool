// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Customize Ribbon (CUI; CUIView and RibbonCustomization in ArchiApp/RibbonCustomization.swift): user panels on any tab
// (title, tab, ordered command lines), move panels and commands, hide built-in panels by title, export / import the
// same "oanarina-archi-cui" JSON file as the Mac (with the quick access toolbar), reset. Stored in the preferences.
import { h, clear } from "../dom";
import { icon } from "../icons";
import { prefs, RIBBON_TABS, RibbonCustomization, CustomRibbonPanel } from "../prefs";
import { toolWindow, flatButton, iconButton, textField, picker, label, note, downloadText, pickTextFile, WindowHandle } from "./ui";
import { app, syncEnginePrefs } from "./context";
import { quickAccessSymbol } from "./quickaccess";

export function emptyCustomization(): RibbonCustomization { return { format: "oanarina-archi-cui", version: 1, panels: [], hiddenPanels: [] }; }
function uuid() { return (crypto as any).randomUUID ? (crypto as any).randomUUID().toUpperCase() : "P" + Math.random().toString(36).slice(2); }
export function panelSymbol(p: CustomRibbonPanel, line: string) { return p.symbols?.[line] ?? quickAccessSymbol(line.split(" ")[0]); }

/** Command lines whose command is not registered (reported on import). */
export function unknownCommands(c: RibbonCustomization): string[] {
  const a = app();
  return c.panels.flatMap((p) => p.commands).filter((l) => !a.lookup(l.split(" ")[0]));
}
/** Parses a customisation file; throws with the Mac message when it is not one. */
export function decodeCustomization(text: string): RibbonCustomization {
  let j: any;
  try { j = JSON.parse(text); } catch { throw new Error("Not an Oanarina Archi Tool ribbon customisation file."); }
  if (!j || typeof j !== "object" || (j.format ?? "oanarina-archi-cui") !== "oanarina-archi-cui") throw new Error("Not an Oanarina Archi Tool ribbon customisation file.");
  const panels: CustomRibbonPanel[] = (Array.isArray(j.panels) ? j.panels : []).map((p: any) => ({
    id: String(p.id ?? uuid()), title: String(p.title ?? "Custom"), tab: String(p.tab ?? "Home"), commands: (p.commands ?? []).map(String), symbols: p.symbols && typeof p.symbols === "object" ? p.symbols : {},
  }));
  return { format: "oanarina-archi-cui", version: Number(j.version ?? 1), panels, hiddenPanels: (j.hiddenPanels ?? []).map(String), ...(Array.isArray(j.quickAccess) ? { quickAccess: j.quickAccess.map(String) } : {}) };
}
export function encodeCustomization(c: RibbonCustomization): string {
  const sortKeys = (v: any): any => Array.isArray(v) ? v.map(sortKeys) : v && typeof v === "object" ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, sortKeys(v[k])])) : v;
  return JSON.stringify(sortKeys(c), null, 2);
}
export function setCustomization(c: RibbonCustomization) {
  const { quickAccess: _q, ...rest } = c;
  void _q;
  prefs.set("ribbonCustomization", rest as RibbonCustomization);
  void syncEnginePrefs();
}

let win: WindowHandle | null = null;
export function openCUI() {
  if (win) { win.focus(); return; }
  let custom = prefs.ribbon;
  let selected: string | null = null;
  let newCommand = "", hideTitle = "", message = "";
  win = toolWindow("cui", "Customize Ribbon", 680, 460, (body) => {
    body.style.flexDirection = "column";
    body.style.padding = "12px";
    body.style.gap = "8px";
    body.style.overflow = "auto";
    const save = () => setCustomization(custom);
    const render = () => {
      clear(body);
      body.append(h("div", { class: "drow" }, label("Customize Ribbon", { bold: true }), h("span", { class: "spacer" }),
        flatButton("Import…", () => void importFile(), { compact: true }), flatButton("Export…", () => void exportFile(), { compact: true }),
        flatButton("Reset", () => { custom = emptyCustomization(); selected = null; save(); render(); }, { compact: true })));
      const list = h("div", { class: "dlist", style: { width: "220px", height: "260px" } });
      for (const p of custom.panels) {
        const r = h("div", { class: "li small" + (selected === p.id ? " sel" : ""), text: `${p.tab} ▸ ${p.title}` });
        r.addEventListener("click", () => { selected = p.id; render(); });
        list.append(r);
      }
      const movePanel = (d: number) => {
        const i = custom.panels.findIndex((p) => p.id === selected);
        if (i < 0) return;
        const same = custom.panels.map((p, k) => (p.tab === custom.panels[i].tab ? k : -1)).filter((k) => k >= 0);
        const k = same.indexOf(i), j = same[k + d];
        if (j === undefined) return;
        [custom.panels[i], custom.panels[j]] = [custom.panels[j], custom.panels[i]];
        save(); render();
      };
      const left = h("div", { class: "dcol", style: { gap: "4px" } }, label("Panels", { dim: true }), list,
        h("div", { class: "drow", style: { gap: "2px" } },
          iconButton("plus", "New panel", () => { const p = { id: uuid(), title: "My Tools", tab: "Home", commands: [], symbols: {} }; custom.panels.push(p); selected = p.id; save(); render(); }),
          iconButton("minus", "Delete panel", () => { custom.panels = custom.panels.filter((p) => p.id !== selected); selected = null; save(); render(); }, { disabled: !selected }),
          iconButton("arrow.up", "Move panel left", () => movePanel(-1), { disabled: !selected }),
          iconButton("arrow.down", "Move panel right", () => movePanel(1), { disabled: !selected })));
      const p = custom.panels.find((x) => x.id === selected);
      let right: HTMLElement;
      if (p) {
        const title = textField("Title", p.title, (v) => { p.title = v; save(); list.querySelector(".li.sel")!.textContent = `${p.tab} ▸ ${p.title}`; });
        title.style.width = "100%";
        const cmds = p.commands.map((line, k) => h("div", { class: "sc-row" }, h("span", { class: "ic" }, icon(panelSymbol(p, line), 13, 1.7)), h("span", { class: "mono", text: line }), h("span", { class: "spacer", style: { flex: "1" } }),
          iconButton("arrow.up", "Move up", () => { [p.commands[k - 1], p.commands[k]] = [p.commands[k], p.commands[k - 1]]; save(); render(); }, { disabled: k === 0 }),
          iconButton("arrow.down", "Move down", () => { [p.commands[k + 1], p.commands[k]] = [p.commands[k], p.commands[k + 1]]; save(); render(); }, { disabled: k === p.commands.length - 1 }),
          iconButton("minus.circle", "Remove", () => { p.commands.splice(k, 1); save(); render(); })));
        const add = () => {
          const line = newCommand.trim();
          if (!line) return;
          if (!app().lookup(line.split(" ")[0])) { message = `Unknown command: ${line}`; render(); return; }
          p.commands.push(line.toUpperCase()); newCommand = ""; message = ""; save(); render();
        };
        right = h("div", { class: "dcol", style: { gap: "6px", minWidth: "300px", flex: "1" } }, title,
          picker(RIBBON_TABS.map((t) => ({ value: t, title: t })), p.tab, (v) => { p.tab = v; save(); render(); }, { label: "Tab", width: 160 }),
          ...cmds,
          h("div", { class: "drow", style: { width: "100%", flexWrap: "nowrap" } }, (() => { const f = textField("Command (e.g. ZOOM E)", newCommand, (v) => { newCommand = v; }, { onSubmit: () => add() }); f.style.flex = "1"; return f; })(), flatButton("Add", () => add(), { compact: true })));
      } else right = h("div", { class: "dlabel dim", text: "Select or add a panel.", style: { minWidth: "300px" } });
      body.append(h("div", { class: "drow", style: { alignItems: "flex-start", gap: "10px", flexWrap: "nowrap" } }, left, right), h("div", { class: "hsep" }), label("Hidden built-in panels", { dim: true }));
      const hideField = textField("Panel title (e.g. Selection)", hideTitle, (v) => { hideTitle = v; }, { width: 220, onSubmit: () => hide() });
      const hide = () => { const t = hideTitle.trim(); if (t && !custom.hiddenPanels.includes(t)) { custom.hiddenPanels.push(t); save(); } hideTitle = ""; render(); };
      body.append(h("div", { class: "drow" }, hideField, flatButton("Hide", () => hide(), { compact: true }),
        ...custom.hiddenPanels.map((t) => flatButton(`${t} ✕`, () => { custom.hiddenPanels = custom.hiddenPanels.filter((x) => x !== t); save(); render(); }, { compact: true }))));
      if (message) body.append(note(message));
    };
    const exportFile = async () => {
      const text = encodeCustomization({ ...custom, quickAccess: prefs.quickAccess });
      const n = app().engine.native;
      if (n?.writeTextFile) {
        const p = await n.saveFileDialog({ title: "Export Ribbon Customisation", defaultPath: "Ribbon.archicui.json", filters: [{ name: "JSON", extensions: ["json"] }] });
        if (!p) return;
        message = (await n.writeTextFile(p, text)) ? "Exported." : `Cannot write ${p}.`;
      } else { downloadText("Ribbon.archicui.json", text); message = "Exported."; }
      render();
    };
    const importFile = async () => {
      const n = app().engine.native;
      let text: string | null;
      if (n?.readTextFile) { const p = await n.openFileDialog({ title: "Import Ribbon Customisation", filters: [{ name: "JSON", extensions: ["json"] }] }); if (!p) return; text = await n.readTextFile(p); }
      else text = await pickTextFile(".json");
      if (text === null) return;
      try {
        const c = decodeCustomization(text);
        if (c.quickAccess?.length) prefs.set("quickAccess", c.quickAccess.filter((q) => app().lookup(q)));
        custom = { ...c }; delete (custom as any).quickAccess;
        setCustomization(custom);
        const unknown = unknownCommands(custom);
        message = unknown.length ? "Imported; unknown commands: " + unknown.join(", ") : "Imported.";
      } catch (e: any) { message = e?.message ?? String(e); }
      render();
    };
    render();
  }, () => { win = null; });
  win.el.style.minWidth = "620px"; win.el.style.minHeight = "420px";
}
