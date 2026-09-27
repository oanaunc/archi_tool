// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Settings window (OPTIONS, Ctrl+,): PreferencesView in ArchiApp/Preferences.swift with the same six pages — General,
// Drafting, Display, Shortcuts, Toolbar, Agents (AgentSettings.swift) — sections, labels, ranges and defaults.
import { h, clear } from "../dom";
import { icon } from "../icons";
import { showMenu, MenuItem } from "../ui/menu";
import { prefs, UNITS, UNIT_ABBR, SNAP_KINDS, ACCENT_PRESETS, CANVAS_PRESETS, RIBBON_TABS, DEFAULT_QUICK_ACCESS, DraftDefaults, PrefKey } from "../prefs";
import { toolWindow, section, row, note, label, flatButton, iconButton, toggle, picker, segmented, stepper, textField, numberField, slider, alertDialog, downloadText, pickTextFile, WindowHandle } from "./ui";
import { app, folders, cachedFolders, reveal, tilde, templatesFolder, scriptsFolder, syncEnginePrefs } from "./context";
import { KeyCombo, RESERVED } from "./shortcuts";
import { quickAccessSymbol } from "./quickaccess";
import ui from "../data/ui.generated.json";

export type SettingsTab = "General" | "Drafting" | "Display" | "Shortcuts" | "Toolbar" | "Agents";
const TABS: [SettingsTab, string][] = [["General", "gearshape"], ["Drafting", "pencil.and.ruler"], ["Display", "paintpalette"], ["Shortcuts", "keyboard"], ["Toolbar", "menubar.rectangle"], ["Agents", "antenna.radiowaves.left.and.right"]];
const POLAR = [5, 10, 15, 18, 22.5, 30, 45, 90];

let current: SettingsTab = "General";
let win: WindowHandle | null = null;
let rerender: (() => void) | null = null;

/** PreferencesWindow.show(tab). */
export function openSettings(tab?: SettingsTab | string) {
  const t = TABS.find(([n]) => n.toLowerCase() === String(tab ?? "").toLowerCase())?.[0];
  if (t) current = t;
  if (win) { win.focus(); rerender?.(); return; }
  void folders().then(() => rerender?.());
  win = toolWindow("settings", "Settings", 680, 520, (body) => {
    const side = h("div", { class: "prefs-side" });
    const main = h("div", { class: "prefs-main" });
    body.append(h("div", { class: "prefs" }, side, h("div", { class: "vsep" }), main));
    rerender = () => {
      clear(side);
      for (const [name, sym] of TABS) {
        const b = h("button", { class: "ptabbtn" + (current === name ? " sel" : "") }, icon(sym, 13, 1.7), h("span", { text: name }));
        b.addEventListener("click", () => { current = name; rerender?.(); });
        side.append(b);
      }
      side.append(h("span", { class: "spacer" }), flatButton("Reset to Defaults", async () => {
        const r = await alertDialog("Reset all settings to their defaults?", "Colors, drafting defaults, shortcuts, the quick access toolbar and autosave go back to the factory settings.", ["Reset", "Cancel"]);
        if (r === 0) prefs.resetToDefaults();
      }, { compact: true }));
      const scroll = main.scrollTop;
      clear(main);
      switch (current) {
        case "General": general(main); break;
        case "Drafting": drafting(main); break;
        case "Display": display(main); break;
        case "Shortcuts": shortcuts(main); break;
        case "Toolbar": toolbar(main); break;
        case "Agents": agents(main); break;
      }
      main.scrollTop = scroll;
    };
    rerender();
  }, () => { win = null; rerender = null; offPrefs(); });
  win.el.style.minWidth = "640px"; win.el.style.minHeight = "460px";
  const offPrefs = prefs.on(() => { if (!editing) rerender?.(); void syncEnginePrefs(); });
}
/** True while a text field of the window is edited (prefs changes then do not rebuild the page under the cursor). */
let editing = false;
function quiet<T>(f: () => T): T { editing = true; try { return f(); } finally { editing = false; } }
function setPref<K extends PrefKey>(k: K, v: any) { prefs.set(k, v); }

// ---- General ----
function folderRow(title: string, key: "templatesFolder" | "scriptsFolder" | "exportFolder", defaultPath: string | null) {
  const path = prefs.get(key);
  const shown = path ? tilde(path) : defaultPath ? tilde(defaultPath) + " (default)" : "Next to the drawing (default)";
  const n = app().engine.native;
  const els = [label(title, { width: 120 }), h("span", { class: "fpath" + (path ? "" : " def"), text: shown, title: shown }),
    flatButton("Choose…", async () => { const p = n?.chooseFolder ? await n.chooseFolder({ title: `Choose the ${title.toLowerCase()} folder`, defaultPath: path || defaultPath || undefined }) : null; if (p) setPref(key, p); }, { compact: true, disabled: !n?.chooseFolder })];
  const target = path || defaultPath;
  if (target) els.push(flatButton("Reveal", () => void reveal(target), { compact: true }));
  if (path) els.push(flatButton("Reset", () => setPref(key, ""), { compact: true }));
  return h("div", { class: "folder-row" }, ...els);
}

function general(main: HTMLElement) {
  const f = cachedFolders();
  const minutes = prefs.get("autosaveMinutes");
  main.append(
    section("Autosave and recovery",
      row(toggle("Autosave", minutes > 0, (on) => setPref("autosaveMinutes", on ? Math.max(minutes, 5) : 0)),
        stepper((v) => (v > 0 ? `every ${v} min` : "off"), minutes, 0, 120, (v) => setPref("autosaveMinutes", v), { disabled: minutes === 0 })),
      note("Unsaved changes are written to a recovery file; after a crash the Start screen offers to restore them."),
      flatButton("Show Recovery Folder", async () => reveal((await folders()).recovery), { compact: true })),
    section("Crash reports",
      toggle("Save a crash report if the app quits unexpectedly", prefs.get("crashReports"), (on) => { setPref("crashReports", on); void app().engine.native?.setSetting?.("crashReports", on); }),
      note("Off by default. Reports hold the app and Windows version and the crashing code's stack — no drawing contents or file names — and are only sent if you choose to after reviewing them.")),
    section("Recent files",
      stepper((v) => `Remember ${v} documents`, prefs.get("recentLimit"), 1, 50, (v) => { setPref("recentLimit", v); void app().engine.native?.setSetting?.("recentLimit", v); }),
      flatButton("Clear Recent Documents", () => { void app().engine.native?.clearRecent(); app().print("Recent documents cleared."); }, { compact: true })),
    section("New drawings",
      picker(UNITS.map((u) => ({ value: u, title: `${u[0].toUpperCase() + u.slice(1)} (${UNIT_ABBR[u]})` })), prefs.get("defaultUnits"), (v) => setPref("defaultUnits", v), { width: 200, label: "Default units" })),
    section("File locations",
      folderRow("Templates", "templatesFolder", f?.templates ?? null),
      folderRow("Script library", "scriptsFolder", f?.scripts ?? null),
      folderRow("Export & publish", "exportFolder", null),
      h("div", { class: "folder-row" }, label("Autosave / recovery", { width: 120 }), h("span", { class: "fpath def", text: f ? tilde(f.recovery) : "" }))),
    section("Scripts",
      toggle("Run startup.js from the script library in every new window", prefs.get("runStartupScript"), (on) => setPref("runStartupScript", on)),
      flatButton("Open Script Library", async () => reveal(await scriptsFolder()), { compact: true })),
  );
}

// ---- Drafting ----
function drafting(main: HTMLElement) {
  const d = prefs.get("draft");
  const set = (patch: Partial<DraftDefaults>) => setPref("draft", { ...prefs.get("draft"), ...patch });
  const snaps = h("div", { class: "chkgrid", style: { gridTemplateColumns: "repeat(auto-fill, minmax(130px, 1fr))" } });
  for (const k of SNAP_KINDS) snaps.append(toggle(k[0].toUpperCase() + k.slice(1), d.snapModes.includes(k), (on) => {
    const m = new Set(prefs.get("draft").snapModes); if (on) m.add(k); else m.delete(k);
    set({ snapModes: SNAP_KINDS.filter((x) => m.has(x)) });
  }));
  main.append(
    section("Grid and snap (new drawings)",
      toggle("Show grid", d.showGrid, (v) => set({ showGrid: v })),
      toggle("Grid snap", d.gridSnap, (v) => set({ gridSnap: v })),
      row(label("Grid spacing (mm)"), numberField(d.gridSpacing, (v) => quiet(() => set({ gridSpacing: v })), { width: 90, positive: true })),
      toggle("Ortho", d.ortho, (v) => set({ ortho: v })),
      toggle("Polar tracking", d.polarTracking, (v) => set({ polarTracking: v })),
      picker(POLAR.map((a) => ({ value: a, title: `${a}°` })), d.polarIncrement, (v) => set({ polarIncrement: v }), { width: 110, label: "Polar increment" }),
      toggle("Dynamic input", d.dynamicInput, (v) => set({ dynamicInput: v })),
      toggle("Show lineweights", d.lineweightDisplay, (v) => set({ lineweightDisplay: v }))),
    section("Object snaps (new drawings)",
      toggle("Object snap on", d.objectSnap, (v) => set({ objectSnap: v })),
      snaps,
      row(flatButton("Apply to Open Drawings", () => applyDraftToOpenDrawings(), { compact: true }), note("These settings are used by every new drawing."))),
  );
}

/** "Apply to Open Drawings": this window now, the other windows through the storage event (index.ts listens). */
export function applyDraftToOpenDrawings() {
  void applyDraftHere();
  try { localStorage.setItem("archi.broadcast.applyDraft", String(Date.now())); } catch {}
}
export async function applyDraftHere() {
  const a = app();
  await a.tryCall("drafting.defaults", { draft: prefs.get("draft") });
  await a.refresh(["sysvars", "drawing"]);
}

// ---- Display ----
function display(main: HTMLElement) {
  const accents = row(...ACCENT_PRESETS.map(([name, hex]) => {
    const b = h("button", { class: "swatch-btn" + (prefs.accent.toLowerCase() === hex.toLowerCase() ? " sel" : ""), style: { background: hex }, title: name, "aria-label": name });
    b.addEventListener("click", () => setPref("accentHex", hex)); return b;
  }), colorWell("Custom", prefs.accent, (v) => setPref("accentHex", v)));
  const canvases = row(...CANVAS_PRESETS.map(([name, hex]) => {
    const b = h("button", { class: "canvas-swatch" + (prefs.canvasColor.toLowerCase() === hex.toLowerCase() ? " sel" : ""), style: { background: hex }, title: name, "aria-label": name });
    b.addEventListener("click", () => setPref("canvasHex", hex)); return b;
  }), colorWell("Custom", prefs.canvasColor, (v) => setPref("canvasHex", v)));
  const pct = label(`${prefs.cursorSize}% of the view`, { dim: true, mono: true });
  main.append(
    section("Theme",
      segmented([{ value: "dark", title: "Dark" }, { value: "light", title: "Light" }], prefs.get("theme"), (v) => setPref("theme", v as any), 220),
      note("Applies to the ribbon, panels and dialogs at once; the drawing background is set below.")),
    section("Accent color", accents),
    section("2D canvas background", canvases),
    section("Crosshair",
      row(label("Size"), slider(1, 100, 1, prefs.cursorSize, (v) => { pct.textContent = `${v}% of the view`; quiet(() => setPref("cursorSize", v)); }, 240), pct),
      note("Same as the CURSORSIZE command; 100 draws a full-screen crosshair.")),
  );
}
function colorWell(title: string, value: string, onChange: (hex: string) => void) {
  const i = h("input", { type: "color", class: "colorwell", value: value.length === 7 ? value : "#F5C518", title }) as HTMLInputElement;
  i.addEventListener("change", () => onChange(i.value.toUpperCase()));
  return h("label", { class: "field-row" }, h("span", { text: title }), i);
}

// ---- Shortcuts ----
let recording: ((c: KeyCombo | null) => void) | null = null;
let combo: KeyCombo | null = null;
let commandText = "";
let message = "";
let search = "";

function startRecording(done: (c: KeyCombo | null) => void) {
  recording = done;
  const onKey = (e: KeyboardEvent) => {
    const c = KeyCombo.fromEvent(e);
    if (e.key === "Escape") { cleanup(); done(null); }
    else if (c) { cleanup(); done(c); }
    e.preventDefault(); e.stopPropagation();
  };
  const cleanup = () => { removeEventListener("keydown", onKey, true); recording = null; };
  addEventListener("keydown", onKey, true);
}

function shortcuts(main: HTMLElement) {
  const map = prefs.get("shortcuts");
  const recBtn = flatButton(recording ? "Press keys… (Esc cancels)" : combo?.toString() ?? "Record Shortcut", () => {
    startRecording((c) => { combo = c; message = ""; rerender?.(); });
    rerender?.();
  }, { prominent: !!recording });
  recBtn.style.minWidth = "150px";
  const cmdField = textField("Command (e.g. WALL or ZOOM E)", commandText, (v) => { commandText = v; assignBtn.disabled = !combo || !commandText.trim(); }, { width: 220, onSubmit: () => assign() });
  const assignBtn = flatButton("Assign", () => assign(), { compact: true, disabled: !combo || !commandText.trim() });
  const assigned = Object.entries(map).sort((a, b) => a[1].localeCompare(b[1]));
  const list = assigned.length ? assigned.map(([k, v]) => h("div", { class: "sc-row" }, h("span", { class: "keys", text: KeyCombo.parse(k)?.toString() ?? k }), h("span", { class: "mono", text: v }), h("span", { class: "spacer", style: { flex: "1" } }),
    iconButton("trash", "Remove", () => { const m = prefs.get("shortcuts"); delete m[k]; setPref("shortcuts", m); })))
    : [h("div", { class: "dlabel dim", text: "No custom shortcuts yet." })];
  const results = h("div", { class: "dcol", style: { width: "100%", gap: "4px" } });
  const renderResults = () => {
    clear(results);
    const q = search.trim().toLowerCase();
    if (!q) return;
    const byCommand = new Map<string, string[]>();
    for (const [k, v] of Object.entries(prefs.get("shortcuts"))) { const c = v.split(" ")[0].toUpperCase(); byCommand.set(c, [...(byCommand.get(c) ?? []), KeyCombo.parse(k)?.toString() ?? k]); }
    const cmds = [...app().hello.commands].sort((a, b) => a.name.localeCompare(b.name)).filter((c) => c.name.toLowerCase().includes(q) || c.aliases.some((a) => a.toLowerCase() === q) || c.summary.toLowerCase().includes(q)).slice(0, 40);
    for (const c of cmds) {
      const set = flatButton("Set", () => { commandText = c.name; startRecording((k) => { combo = k; message = ""; rerender?.(); }); rerender?.(); }, { compact: true, help: `Record keys for ${c.name}, then press Assign` });
      results.append(h("div", { class: "sc-row" }, h("span", { class: "cmdname", text: c.name }), h("span", { class: "sum", text: c.summary }), h("span", { class: "mono", text: (byCommand.get(c.name) ?? []).join(" ") }), set));
    }
  };
  const searchField = textField("Search commands to assign", search, (v) => { search = v; renderResults(); }, { width: 240 });
  renderResults();
  main.append(
    section("Assign a shortcut",
      row(recBtn, cmdField, assignBtn),
      message ? note(message, "accent") : null,
      note("Shortcuts need Ctrl (or a function key) so that plain typing still goes to the command line. A custom shortcut overrides the menu shortcut with the same keys.")),
    section("Custom shortcuts", ...list),
    section("Commands",
      h("div", { class: "drow", style: { width: "100%" } }, searchField, h("span", { class: "spacer" }), flatButton("Export…", () => void exportShortcuts(), { compact: true }), flatButton("Import…", () => void importShortcuts(), { compact: true })),
      results),
    section("Built-in",
      note("F3 Osnap · F7 Grid · F8 Ortho · F9 Snap · F10 Polar · F11 Object snap tracking · F12 Dynamic input · Ctrl+K Command search · Ctrl+Alt+1…4 workspaces views · See Help ▸ Keyboard Shortcuts.")),
  );
}

function assign() {
  const c = combo;
  if (!c) return;
  const cmd = commandText.trim();
  if (!cmd) return;
  if (!c.isAssignable) { message = `${c} cannot be used: add Ctrl.`; rerender?.(); return; }
  const first = cmd.split(" ")[0];
  if (!app().lookup(first)) { message = `Unknown command ${first.toUpperCase()}.`; rerender?.(); return; }
  const map = prefs.get("shortcuts");
  const previous = map[c.normalized];
  map[c.normalized] = cmd.toUpperCase();
  let n = `${c} now runs ${cmd.toUpperCase()}.`;
  if (RESERVED[c.normalized]) n += ` It replaces the menu shortcut for ${RESERVED[c.normalized]}.`;
  if (previous && previous.toUpperCase() !== cmd.toUpperCase()) n += ` (Was ${previous}.)`;
  message = n; combo = null; commandText = "";
  setPref("shortcuts", map);
}

async function exportShortcuts() {
  const map = prefs.get("shortcuts");
  const sorted = Object.fromEntries(Object.entries(map).sort((a, b) => a[0].localeCompare(b[0])));
  const text = JSON.stringify(sorted, null, 2);
  const n = app().engine.native;
  if (n?.saveFileDialog && n.writeTextFile) {
    const p = await n.saveFileDialog({ title: "Export Shortcuts", defaultPath: "Archi Shortcuts.json", filters: [{ name: "JSON", extensions: ["json"] }] });
    if (!p) return;
    message = (await n.writeTextFile(p, text)) ? `Exported ${Object.keys(map).length} shortcut(s).` : `Cannot write ${p}.`;
  } else { downloadText("Archi Shortcuts.json", text); message = `Exported ${Object.keys(map).length} shortcut(s).`; }
  rerender?.();
}
async function importShortcuts() {
  const n = app().engine.native;
  let text: string | null = null;
  if (n?.readTextFile) { const p = await n.openFileDialog({ title: "Import Shortcuts", filters: [{ name: "JSON", extensions: ["json"] }] }); if (!p) return; text = await n.readTextFile(p); }
  else text = await pickTextFile(".json");
  let parsed: Record<string, string> | null = null;
  try { const j = JSON.parse(text ?? ""); if (j && typeof j === "object" && !Array.isArray(j) && Object.values(j).every((v) => typeof v === "string")) parsed = j; } catch {}
  if (!parsed) { message = "Not a shortcuts file."; rerender?.(); return; }
  const map = prefs.get("shortcuts");
  let count = 0;
  for (const [k, v] of Object.entries(parsed)) { const c = KeyCombo.parse(k); if (c?.isAssignable) { map[c.normalized] = v; count++; } }
  message = `Imported ${count} shortcut(s).`;
  setPref("shortcuts", map);
}

// ---- Toolbar ----
let newCommand = "";
let toolbarMessage = "";
function toolbar(main: HTMLElement) {
  const qa = prefs.quickAccess;
  const move = (i: number, d: number) => { const l = prefs.quickAccess; const j = i + d; if (j < 0 || j >= l.length) return; [l[i], l[j]] = [l[j], l[i]]; setPref("quickAccess", l); };
  const rows = qa.map((name, i) => h("div", { class: "sc-row" }, h("span", { class: "ic" }, icon(quickAccessSymbol(name), 13, 1.7)), h("span", { class: "mono", text: name }),
    h("span", { class: "sum", text: app().lookup(name)?.summary ?? "" }),
    iconButton("arrow.up", "Move left", () => move(i, -1), { disabled: i === 0 }), iconButton("arrow.down", "Move right", () => move(i, 1), { disabled: i === qa.length - 1 }),
    iconButton("minus.circle", "Remove", () => { const l = prefs.quickAccess; l.splice(i, 1); setPref("quickAccess", l); })));
  const add = () => {
    const def = app().lookup(newCommand.trim());
    if (!def) { toolbarMessage = "Unknown command."; rerender?.(); return; }
    const l = prefs.quickAccess; if (!l.includes(def.name)) l.push(def.name);
    newCommand = ""; toolbarMessage = ""; setPref("quickAccess", l);
  };
  const browse = flatButton("Browse", () => showMenu(browseMenu((name) => { const l = prefs.quickAccess; if (!l.includes(name)) { l.push(name); setPref("quickAccess", l); } }), browse), { compact: true });
  const tabs = h("div", { class: "chkgrid", style: { gridTemplateColumns: "repeat(auto-fill, minmax(120px, 1fr))" } });
  const hidden = prefs.hiddenRibbonTabs;
  for (const t of RIBBON_TABS) tabs.append(toggle(t, !hidden.includes(t), (on) => {
    let l = prefs.hiddenRibbonTabs.filter((x) => x !== t);
    if (!on && t !== "Home") l = [...l, t];
    setPref("hiddenRibbonTabs", l);
  }, { disabled: t === "Home" }));
  main.append(
    section("Quick access toolbar", ...rows,
      row(textField("Command name (e.g. MATCHPROP)", newCommand, (v) => { newCommand = v; }, { width: 220, onSubmit: () => add() }), flatButton("Add", () => add(), { compact: true }), browse,
        flatButton("Restore Default", () => setPref("quickAccess", [...DEFAULT_QUICK_ACCESS]), { compact: true })),
      toolbarMessage ? note(toolbarMessage, "danger") : null),
    section("Ribbon tabs", tabs, note("Hidden tabs keep their commands on the menus and the command line.")),
  );
}

/** Browse menu: the menu-bar catalogue (CommandCatalog.menus + coverageMenus): menu ▸ item → the item's command. */
export function browseMenu(pick: (name: string) => void): MenuItem[] {
  const menus = ((ui as any).menus ?? []) as any[];
  const a = app();
  const conv = (items: any[]): MenuItem[] => items.flatMap((it): MenuItem[] => {
    const sub = it.submenu ?? it.items;
    if (Array.isArray(sub)) { const s = conv(sub); return s.length ? [{ title: it.title, submenu: s }] : []; }
    if (!it.title || !it.command || String(it.command).startsWith("@") || /\{/.test(it.title)) return [];
    const names = [it.command, ...(it.names ?? [])].map((n: string) => n.split(" ")[0]);
    const n = names.find((x: string) => a.lookup(x));
    return n ? [{ title: it.title, action: () => pick(a.lookup(n)!.name) }] : [];
  });
  return menus.map((m) => ({ title: m.menu ?? m.title, submenu: conv(m.items ?? []) })).filter((m) => m.submenu.length);
}

// ---- Agents (AgentPrefs) ----
let agentStatus = "";
let revealToken = false;
function agents(main: HTMLElement) {
  const state = agentServerState();
  const port = numberField(prefs.get("agentPort"), (v) => quiet(() => setPref("agentPort", Math.round(v))), { width: 70, positive: true, integer: true });
  const token = state.token || "";
  main.append(
    section("Local agent server",
      row(h("span", { style: { width: "8px", height: "8px", borderRadius: "50%", background: state.running ? "#40CC66" : "var(--faint)", display: "inline-block" } }),
        label(state.running ? `Listening on http://127.0.0.1:${state.port}/rpc` : "Stopped", { bold: true }), h("span", { class: "spacer" }),
        flatButton(state.running ? "Stop" : "Start", () => toggleAgentServer(!state.running), { prominent: !state.running })),
      row(label("Port"), port, note("(127.0.0.1 only; restart the server to apply)")),
      toggle("Start the agent server when the app launches", prefs.get("agentAutoStart"), (on) => setPref("agentAutoStart", on)),
      h("div", { class: "folder-row" }, label("Token", { width: 40 }), h("span", { class: "fpath", style: { direction: "ltr" }, text: revealToken && token ? token : "•".repeat(24) }),
        iconButton(revealToken ? "eye.slash" : "eye", revealToken ? "Hide" : "Reveal", () => { revealToken = !revealToken; rerender?.(); }),
        flatButton("Copy Token", () => { if (token) void navigator.clipboard?.writeText(token); agentStatus = "Token copied. Send it as “Authorization: Bearer <token>”."; rerender?.(); }, { compact: true, disabled: !token })),
      h("div", { class: "folder-row" }, label("Info file", { width: 60 }), h("span", { class: "fpath def", text: state.infoFile ? tilde(state.infoFile) : tilde((cachedFolders()?.userData ?? "") + "\\agent.json") })),
      note("The token changes every launch. Agents can also read the port and token from the info file while the server runs."),
      agentStatus ? note(agentStatus, "accent") : null),
    section("Connect Claude",
      h("div", { text: "Claude Desktop and Claude Code talk to Oanarina Archi Tool through the bundled archi-cli in MCP mode, or to this running window through the local agent server." }),
      flatButton("Show Setup Instructions…", () => void app().runCommand("CONNECTCLAUDE"), { prominent: true })),
  );
}

/** The agent server lives in the Electron main process when a build provides it ("archi:agentServer" event). */
function agentServerState(): { running: boolean; port: number; token?: string; infoFile?: string } {
  const detail: any = { action: "status", port: prefs.get("agentPort") };
  document.dispatchEvent(new CustomEvent("archi:agentServer", { detail }));
  return { running: !!detail.running, port: detail.port ?? prefs.get("agentPort"), token: detail.token, infoFile: detail.infoFile };
}
function toggleAgentServer(start: boolean) {
  const detail: any = { action: start ? "start" : "stop", port: prefs.get("agentPort") };
  document.dispatchEvent(new CustomEvent("archi:agentServer", { detail }));
  agentStatus = detail.handled ? (detail.message ?? "") : "The agent server is not part of this Windows build yet; use archi-cli --mcp.";
  rerender?.();
}

export function settingsOpen() { return !!win; }
export { templatesFolder };
