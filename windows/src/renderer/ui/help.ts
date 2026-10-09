// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Help and window-chrome commands of the Mac UI layer, ported: About window (AboutWindow.swift), Command Reference
// window (CommandReferenceView in ArchiApp.swift), What's New (WhatsNew / WhatsNewView in StudioPanels.swift, shown once
// after an update), the command reference export (EXPORTCOMMANDS, CommandReferenceExport in AppCommandsExtra.swift) and
// the shell side of ABOUT, COMMANDSEARCH, CLEANSCREENON/OFF, HISTORYPANEL, STARTSCREEN, SAMPLEHOUSE, WHATSNEW, plus the
// Block Library and Family Editor windows from the "More" menus. Menu clicks run these directly (shell-commands.ts);
// the same commands typed on the command line run in the engine, which answers with `host` notifications handled here.
import "./help.css";
import type { App } from "../app";
import { h, clear } from "../dom";
import { icon } from "../icons";
import ui from "../data/ui.generated.json";
import { toolWindow, flatButton, downloadText } from "../dialogs/ui";
import { registerShellCommand } from "./shell-commands";
import { WEBSITE } from "./menubar";

const VERSION: { short: string; build: string } = (ui as any).appVersion ?? { short: "1.0.0", build: "1" };
export const versionText = () => `Version ${VERSION.short} (${VERSION.build})`;

function openURL(app: App, url: string) { void app.action(`@openURL:${url}`); }

// ---- About (AboutWindow.swift) ----
const CREDITS: [string, string][] = [
  ["LibreCAD", "2D drafting commands, snaps and DXF ideas"],
  ["SolveSpace", "constraint and sketch workflow ideas"],
  ["OpenSCAD", "script-driven solid modelling ideas"],
  ["BRL-CAD", "solid modelling and CSG ideas"],
  ["IfcOpenShell", "IFC4 structure and BIM data ideas"],
  ["CAD Sketcher", "parametric sketch ideas"],
  ["Sverchok", "node-based and generative design ideas"],
];
export function showAbout(app: App) {
  const w = toolWindow("about", "About Oanarina Archi Tool", 460, 640, (body) => {
    const link = h("a", { class: "about-link", href: WEBSITE, text: "www.oanarinaldi.com" });
    link.addEventListener("click", (e) => { e.preventDefault(); openURL(app, WEBSITE); });
    body.append(h("div", { class: "about" },
      h("img", { class: "about-icon", src: "assets/app-icon.png", alt: "" }),
      h("div", { class: "about-name", text: "Oanarina Archi Tool" }),
      h("div", { class: "about-version", text: versionText() }),
      h("div", { class: "about-tag", text: "Drafting, building design, 3D, rendering and scripting for Windows." }),
      h("div", { class: "about-box" },
        h("div", { class: "about-hdr", text: "FREE SOFTWARE" }),
        h("div", { class: "about-small", text: "This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed WITHOUT ANY WARRANTY; see the GNU GPL v3 for details." }),
        h("div", { class: "about-row" }, flatButton("View License", () => openURL(app, "https://www.gnu.org/licenses/gpl-3.0.html"), { compact: true }))),
      h("div", { class: "about-box" },
        h("div", { class: "about-hdr", text: "THANKS" }),
        h("div", { class: "about-small dim", text: "Ideas and algorithms were studied from these free projects (see THIRD-PARTY.md):" }),
        ...CREDITS.map(([n, what]) => h("div", { class: "about-credit" }, h("span", { class: "n", text: n }), h("span", { class: "w", text: what })))),
      h("div", { class: "about-foot" }, h("span", { text: "© Oanarina ·" }), link)));
  });
  w.el.classList.add("about-window");
  // Like the Mac window, sized to its content (font metrics differ between Segoe UI and SF).
  const content = w.body.querySelector(".about") as HTMLElement | null;
  if (content) { const bar = w.el.querySelector(".twin-bar") as HTMLElement | null; w.el.style.height = Math.min(innerHeight - 40, content.scrollHeight + (bar?.offsetHeight ?? 30) + 2) + "px"; }
  w.focus();
}

// ---- Command Reference (CommandReferenceView) ----
export function showCommandReference(app: App) {
  const w = toolWindow("command-reference", "Command Reference", 720, 560, (body) => {
    const count = h("span", { class: "cref-count" });
    const input = h("input", { class: "cref-search", placeholder: "Search commands, aliases, descriptions", spellcheck: false }) as HTMLInputElement;
    const list = h("div", { class: "cref-list" });
    const render = () => {
      const q = input.value.trim().toLowerCase();
      const all = [...(app.hello?.commands ?? [])].sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
      const cmds = all.filter((c) => !q || c.name.toLowerCase().includes(q) || (c.aliases ?? []).some((a) => a.toLowerCase().includes(q)) || c.summary.toLowerCase().includes(q) || c.category.toLowerCase().includes(q));
      count.textContent = `${cmds.length} of ${all.length}`;
      const groups = new Map<string, typeof cmds>();
      for (const c of cmds) { const g = groups.get(c.category) ?? []; g.push(c); groups.set(c.category, g); }
      clear(list);
      for (const cat of [...groups.keys()].sort()) {
        list.append(h("div", { class: "cref-hdr", text: cat.toUpperCase() }));
        for (const c of groups.get(cat)!) list.append(h("div", { class: "cref-row" }, h("span", { class: "n", text: c.name }), h("span", { class: "a", text: (c.aliases ?? []).join(", ") }), h("span", { class: "s", text: c.summary })));
      }
    };
    input.addEventListener("input", render);
    body.append(h("div", { class: "cref" },
      h("div", { class: "cref-top" }, icon("terminal", 14, 1.8), h("span", { class: "cref-title", text: "Command Reference" }), count, h("span", { class: "spacer" }), input),
      h("div", { class: "hsep" }), list));
    render();
    setTimeout(() => input.focus(), 0);
  });
  w.focus();
}

// ---- What's New (StudioPanels.swift WhatsNew) ----
export const WHATS_NEW: [string, string[]][] = [
  ["3D", ["Move gizmo with a Z arrow: drag objects up and down (walls, slabs, columns, components, solids) — GIZMO3D, MOVEZ",
    "Isolate one level or explode levels vertically in the 3D view — LEVELVIEW3D", "Field of view / focal length — FOV",
    "Export the 3D view as PNG, JPEG or TIFF, optionally with a transparent background — VIEWIMAGE"]],
  ["Families", ["Family Editor panel: parameters with formulas, forms (box, extrusion, blend, revolve, sweep, swept blend, voids, arrays), types table, reference planes and profiles, live 3D preview and flexing — FAMILYPANEL"]],
  ["Drafting", ["Click a block or component in the tool palette to place it; Space rotates the preview 90°", "Space while dragging a grip rotates the object 90° about the grip"]],
  ["Sheets", ["Export a sheet as PNG, JPEG or TIFF at any resolution — SHEETIMAGE"]],
  ["Panels", ["Selection info — SELECTIONINFO", "Notifications centre with zoom-to — NOTIFICATIONS", "Navigator overview map — NAVIGATOR"]],
  ["Scripting", ["Event hooks: archi.on(\"selectionChanged\" | \"documentChanged\" | \"elementAdded\" | \"elementRemoved\" | \"saved\" | \"commandEnded\", fn)",
    "Script panels: archi.panel({title, items}) with buttons, numbers and text fields", "Plug-in commands are one undo step"]],
];
export function showWhatsNew() {
  const w = toolWindow("whatsnew", "What's New", 520, 460, (body) => {
    const col = h("div", { class: "whatsnew" }, h("div", { class: "wn-title", text: `What's New in Oanarina Archi Tool ${VERSION.short}` }));
    for (const [sec, lines] of WHATS_NEW) { col.append(h("div", { class: "wn-sec", text: sec })); for (const l of lines) col.append(h("div", { class: "wn-line", text: "• " + l })); }
    col.append(h("div", { class: "wn-note", text: "Type HELP or a command name in the command line to learn more. Show this again with WHATSNEW." }));
    body.append(col);
  });
  w.focus();
}
const LAST_SEEN = "whatsNew.lastSeenVersion";
/** Shown after an update (a different version than last time); a fresh install records the version silently. */
export function whatsNewShouldShow(current: string, lastSeen: string | null) { return lastSeen !== null && lastSeen !== current; }
function whatsNewOnLaunch() {
  let last: string | null = null;
  try { last = localStorage.getItem(LAST_SEEN); localStorage.setItem(LAST_SEEN, VERSION.short); } catch { return; }
  if (whatsNewShouldShow(VERSION.short, last)) setTimeout(showWhatsNew, 1200);
}

// ---- EXPORTCOMMANDS (CommandReferenceExport) ----
/** Where a command is in the UI: the first menu, then ribbon group, that lists it (else "Command line"). */
export function commandLocations(): Map<string, string> {
  const where = new Map<string, string>();
  const note = (cmd: unknown, loc: string) => { const n = typeof cmd === "string" ? cmd.split(" ")[0].toUpperCase() : ""; if (n && !n.startsWith("@") && !where.has(n)) where.set(n, loc); };
  const walkMenu = (items: any[], loc: string) => {
    for (const it of items ?? []) {
      note(it.command, loc);
      for (const n of it.names ?? []) note(n, loc);
      const sub = it.submenu ?? it.items;
      if (Array.isArray(sub)) walkMenu(sub, loc);
    }
  };
  const menus = ((ui as any).menus ?? []) as any[];
  const order = ["Draw", "Modify", "Annotate", "Architecture", "Model", "Analyze"];
  for (const t of order) {
    const m = menus.find((x) => x.title === t);
    if (!m) continue;
    for (const it of m.items ?? []) {
      const sub = it.submenu ?? it.items;
      if (Array.isArray(sub) && (t === "Model" || t === "Analyze" || t === "Architecture")) walkMenu(sub, `${t} ▸ ${it.title}`);
      else walkMenu([it], t);
    }
  }
  for (const tab of ((ui as any).ribbon ?? []) as any[]) for (const g of tab.groups ?? []) {
    const walk = (items: any[]) => { for (const it of items ?? []) { note(it.command, `${tab.tab} ▸ ${g.name}`); for (const n of it.names ?? []) note(n, `${tab.tab} ▸ ${g.name}`); for (const s of it.sections ?? []) walk(s.items); } };
    walk(g.items);
  }
  const tools = menus.find((x) => x.title === "Tools");
  for (const it of tools?.items ?? []) { const sub = it.submenu ?? it.items; if (Array.isArray(sub) && it.title !== "All Commands") walkMenu(sub, `Tools ▸ ${it.title}`); }
  for (const m of menus) if (!order.includes(m.title) && m.title !== "Tools") walkMenu(m.items, m.title === "Oanarina Archi Tool" ? "Application menu" : m.title);
  return where;
}
export function commandReferenceText(app: App, csv: boolean): string {
  const cmds = [...(app.hello?.commands ?? [])].sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  const where = commandLocations();
  const loc = (n: string) => where.get(n.toUpperCase()) ?? "Command line";
  const q = (s: string) => `"${s.replace(/"/g, '""')}"`;
  if (csv) return ["Command,Aliases,Category,Summary,Location", ...cmds.map((d) => [d.name, (d.aliases ?? []).join(" "), d.category, d.summary, loc(d.name)].map(q).join(","))].join("\n") + "\n";
  let out = `# Oanarina Archi Tool — command reference\n\n${cmds.length} commands. Every command also runs from the command line, scripts (\`archi.run\`) and the agent server.\n`;
  const groups = new Map<string, typeof cmds>();
  for (const c of cmds) { const g = groups.get(c.category) ?? []; g.push(c); groups.set(c.category, g); }
  for (const cat of [...groups.keys()].sort()) {
    out += `\n## ${cat}\n\n| Command | Aliases | Summary | Where |\n|---|---|---|---|\n`;
    for (const d of groups.get(cat)!) out += `| \`${d.name}\` | ${(d.aliases ?? []).join(", ")} | ${d.summary.replace(/\|/g, "/")} | ${loc(d.name)} |\n`;
  }
  return out;
}
export async function exportCommandReference(app: App, path = "") {
  const n = app.engine.native;
  let p = path.trim();
  if (!p && n) p = (await n.saveFileDialog({ title: "Export Command Reference", defaultPath: "Oanarina Archi Tool commands.md", filters: [{ name: "Markdown", extensions: ["md"] }, { name: "CSV", extensions: ["csv"] }, { name: "Text", extensions: ["txt"] }] })) ?? "";
  if (!p && n) return;
  const csv = /\.csv$/i.test(p);
  const text = commandReferenceText(app, csv);
  if (n?.writeTextFile && p) await n.writeTextFile(p, text);
  else downloadText(p ? p.split(/[\\/]/).pop()! : "Oanarina Archi Tool commands.md", text);
  app.print(`Exported ${app.hello?.commands?.length ?? 0} commands to ${p || "Oanarina Archi Tool commands.md"}`);
}

// ---- install: shell commands, host notifications and ui targets ----
export function installHelp(app: App, o: { commandSearch: () => void }) {
  const setClean = (on: boolean) => { if (app.cleanScreen !== on) { app.cleanScreen = on; app.emit("ui"); } };
  const startScreen = () => { app.showStart = true; app.emit("start"); };
  const blockLibrary = () => { if (!app.uiHooks.ui?.("window:BlockLibraryWindow")) void app.runCommand("BLOCKLIBRARY"); };
  const familyEditor = () => { if (!app.uiHooks.host?.({ action: "dialog", dialog: "familyEditor" })) void app.runCommand("FAMILY"); };
  registerShellCommand(["ABOUT"], () => showAbout(app));
  registerShellCommand(["COMMANDSEARCH", "CMDSEARCH", "SEARCHCOMMANDS"], () => o.commandSearch());
  registerShellCommand(["CLEANSCREENON", "CLEANSCREEN"], () => { setClean(true); app.print("Clean screen on. CLEANSCREENOFF or Ctrl+0 restores the ribbon and panels."); });
  registerShellCommand(["CLEANSCREENOFF", "RIBBON", "RB"], () => { setClean(false); app.setUI("ribbonCollapsed", false); });
  registerShellCommand(["HISTORYPANEL", "UNDOHISTORY"], () => app.action("@panel:History"));
  registerShellCommand(["STARTSCREEN", "WELCOME"], startScreen);
  registerShellCommand(["SAMPLEHOUSE", "OPENSAMPLE"], () => app.action("@newWindow:sample"));
  registerShellCommand(["WHATSNEW", "RELEASENOTES"], () => showWhatsNew());
  registerShellCommand(["COMMANDREFERENCE"], () => showCommandReference(app));
  registerShellCommand(["EXPORTCOMMANDS"], () => exportCommandReference(app));
  // The "More" menus and Tools menu open the windows (the command line keeps the command-line versions).
  registerShellCommand(["BLOCKLIBRARY"], blockLibrary);
  registerShellCommand(["FAMILY"], familyEditor);
  // File and Edit entries with a native equivalent (Mac: NSDocument open/save panels, performClose, undo manager).
  registerShellCommand(["OPEN"], () => app.open());
  registerShellCommand(["SAVE"], () => app.save());
  registerShellCommand(["SAVEAS"], () => app.save(true));
  registerShellCommand(["FULLSCREEN"], () => { void app.engine.native?.windowControl("fullscreen"); });
  registerShellCommand(["CLOSE"], () => { void app.engine.native?.windowControl("close"); });
  registerShellCommand(["UNDO"], () => app.undo());
  registerShellCommand(["REDO"], () => app.redo());
  registerShellCommand(["IMPORT"], async () => {
    const p = await app.engine.native?.openFileDialog({ title: "Import" });
    if (p) { await app.tryCall("file.import", { path: p }); await app.refresh(["all"]); }
  });

  const prevHost = app.uiHooks.host;
  app.uiHooks.host = (p: any) => {
    switch (p?.action) {
      case "dialog":
        if (p.dialog === "about") { showAbout(app); return true; }
        if (p.dialog === "commandSearch") { o.commandSearch(); return true; }
        if (p.dialog === "whatsNew") { showWhatsNew(); return true; }
        break;
      case "cleanScreen": setClean(!!p.on); return true;
      case "ribbonExpand": app.setUI("ribbonCollapsed", false); return true;
      case "startScreen": startScreen(); return true;
      case "newWindow": if (p.kind === "sample") { void app.action("@newWindow:sample"); return true; } break;
      case "exportCommands": void exportCommandReference(app, String(p.path ?? "")); return true;
    }
    return !!prevHost?.(p);
  };
  const prevUI = app.uiHooks.ui;
  app.uiHooks.ui = (ref: string) => {
    switch (ref) {
      case "window:AboutWindow": showAbout(app); return true;
      case "window:command-reference": showCommandReference(app); return true;
      case "window:whatsnew": showWhatsNew(); return true;
      case "RecentFiles.clear": void app.engine.native?.clearRecent(); return true;
      case "WindowRouter.open": void app.action("@newWindow:sample"); return true;
    }
    return !!prevUI?.(ref);
  };
  document.addEventListener("archi:ready", whatsNewOnLaunch, { once: true });
}
