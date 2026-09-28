// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The menu bar, generated from the Mac menus in docs/windows-parity.json (ArchiApp.swift `commands`): File, Edit, View,
// Draw, Modify, Annotate, Architecture, Model, Analyze, Tools, Window and Help with every entry, submenu, run-time list
// (Open Recent, templates, workspaces, Tools ▸ All Commands) and the Windows keys of their shortcuts (ui/keys.ts).
// Windows conventions on top: the macOS application menu is folded in (About → Help, Settings → Edit ▸ Options…,
// Quit → File ▸ Exit Alt+F4), Hide / Hide Others / Bring All to Front are dropped, Window ▸ Zoom is Maximize and
// Window ▸ New Window is kept; Enter Full Screen has no key (F11 is object snap tracking).
import type { App, Mode } from "../app";
import type { MenuItem } from "./menu";
import ui from "../data/ui.generated.json";
import { newFromTemplateMenu, workspaceMenu, dynamicMenu } from "../dialogs";
import { GUIDE_URL, openContextHelp } from "./windows-conventions";
import { resolveEntry, runEntry, entryEnabled } from "./shell-commands";
import { shortcutLabel } from "./keys";

export const WEBSITE = "https://www.oanarinaldi.com";
const HIDDEN_MENUS = new Set(["Oanarina Archi Tool"]);
const PICKER_MODES: Record<string, Mode> = { "2D Plan": "2D", "3D Model": "3D", Split: "Split", Sheet: "Sheet" };
const SCHEDULE_KINDS = ["walls", "doors", "windows", "rooms", "slabs", "all"]; // ScheduleExporter.kinds

/** Run-time state the menus show (filled by the title bar before a menu opens). */
export const menuState = { recent: [] as { path: string }[], fullScreen: false };

function appMenuItem(title: string): any { return ((ui as any).menus ?? []).find((m: any) => m.title === "Oanarina Archi Tool")?.items?.find((i: any) => i.title === title) ?? {}; }

/** Tools ▸ All Commands: one submenu per category, every command in it (the Mac's `{groups}` list). */
export function allCommandsMenu(app: App): MenuItem[] {
  const groups = new Map<string, string[]>();
  for (const c of app.hello?.commands ?? []) { const g = groups.get(c.category) ?? []; g.push(c.name); groups.set(c.category, g); }
  return [...groups.keys()].sort().map((cat) => ({ title: cat, submenu: groups.get(cat)!.sort().map((n) => ({ title: n, action: () => void app.runCommand(n) })) }));
}

function enabledWhen(app: App, cond: string | undefined): boolean {
  if (!cond) return true;
  if (cond.includes("selection.isEmpty")) return (app.selection?.ids?.length ?? 0) > 0;
  if (cond.includes("layouts.isEmpty")) return (app.info?.layouts?.length ?? 0) > 0;
  return true; // canUndo / canRedo: the engine answers "Nothing to undo."; the user guide is online on Windows
}

function recentMenu(app: App): MenuItem[] {
  const rec = menuState.recent;
  return [
    ...rec.map((r) => ({ title: r.path.split(/[\\/]/).pop() ?? r.path, action: () => void app.open(r.path) })),
    ...(rec.length ? [{ separator: true } as MenuItem] : []),
    { title: "Clear Menu", disabled: !rec.length, action: () => { menuState.recent = []; void app.engine.native?.clearRecent(); } },
  ];
}

export function convertMenu(app: App, items: any[], path: string[]): MenuItem[] {
  const native = app.engine.native;
  return items.flatMap((it): MenuItem[] => {
    if (it.separator) return [{ separator: true }];
    if (it.header !== undefined && !it.title) return [{ header: String(it.header) }];
    if (it.dynamic) {
      const d = String(it.dynamic);
      if (d === "groups") return allCommandsMenu(app);
      return dynamicMenu(d) ?? [];
    }
    const title = String(it.title ?? "");
    const here = [...path, title];
    const sub = Array.isArray(it.submenu) ? it.submenu : Array.isArray(it.items) ? it.items : null;
    if (it.system) {
      if (/Full Screen/.test(title)) return [{ title: menuState.fullScreen ? "Exit Full Screen" : "Enter Full Screen", action: async () => { menuState.fullScreen = !!(await native?.windowControl("fullscreen")); } }];
      if (title === "Minimize") return [{ title, action: () => void native?.windowControl("minimize") }];
      if (title === "Zoom") return [{ title: "Maximize", action: () => void native?.windowControl("maximize") }];
      return []; // Hide, Hide Others, Bring All to Front, Quit (File ▸ Exit)
    }
    if (it.picker && sub) return sub.map((r: any) => ({ title: r.title, checked: app.mode === PICKER_MODES[r.title], action: () => app.setUI("mode", PICKER_MODES[r.title]) }));
    if (sub || (!it.command && !it.ui)) {
      // Submenus, including the ones filled at run time.
      let items: MenuItem[];
      if (title === "Open Recent") items = recentMenu(app);
      else if (title === "New from Template") items = newFromTemplateMenu();
      else if (title === "Workspace") items = workspaceMenu();
      else if (title === "Schedules (CSV)" && !(sub ?? []).length) items = SCHEDULE_KINDS.map((k) => ({ title: `${k[0].toUpperCase()}${k.slice(1)}…`, action: () => void app.action(`@export:csv:${k}`) }));
      else items = convertMenu(app, sub ?? [], here);
      return [{ title, symbol: it.symbol, submenu: items, disabled: !items.length }];
    }
    let entry = { command: it.command as string | undefined, args: it.args as string | undefined, ui: it.ui as string | undefined, names: it.names as string[] | undefined };
    let action: (() => void) | undefined;
    let t = title;
    let shortcut = shortcutLabel(entry, here.join(" ▸ "));
    // Entries whose Mac action is a UI-layer call the catalogue records by its nearest command.
    if (/Help \(F1\)$/.test(title)) { action = () => openContextHelp(app); shortcut = "F1"; }
    else if (title === "Tutorials" && path[0] === "Help") entry = { command: "TUTORIALS", args: undefined, ui: undefined, names: ["TUTORIALS", "TUTORIAL"] };
    else if (entry.command === "@openURL") { const url = /guide/i.test(title) ? GUIDE_URL : WEBSITE; action = () => void app.action(`@openURL:${url}`); }
    else if (entry.command === "@ui:RecentFiles.clear") action = () => { menuState.recent = []; void native?.clearRecent(); };
    else if (entry.command === "@ui:WindowRouter.open") entry.command = "@newWindow:sample";
    // Toggles show their state like the Mac titles.
    if (entry.command === "@panels:toggle") t = app.showPanels ? "Hide Panels" : "Show Panels";
    else if (entry.command === "@cleanScreen") t = app.cleanScreen ? "Exit Clean Screen" : "Clean Screen";
    else if (entry.command === "@scriptConsole") t = app.showScriptConsole ? "Hide Script Console" : "Show Script Console";
    const enabled = action ? true : entryEnabled(app, entry) && enabledWhen(app, it.enabledWhen);
    return [{ title: t, symbol: it.symbol, shortcut, disabled: !enabled, action: action ?? (() => void runEntry(app, entry, resolveEntry(app, entry))) }];
  });
}

/** Every menu of the menu bar, in the Mac order (without the macOS application menu). */
export function buildMenuBar(app: App): { title: string; items: MenuItem[] }[] {
  const native = app.engine.native;
  const menus = ((ui as any).menus ?? []) as any[];
  const out: { title: string; items: MenuItem[] }[] = [];
  for (const m of menus) {
    const title = String(m.title ?? m.menu ?? "");
    if (HIDDEN_MENUS.has(title)) continue;
    const items = convertMenu(app, m.items ?? [], [title]);
    if (title === "File") {
      while (items.length && items[items.length - 1].separator) items.pop();
      items.push({ separator: true }, { title: "Exit", shortcut: "Alt+F4", action: () => void native?.windowControl("quit") });
    } else if (title === "Edit") {
      const settings = appMenuItem("Settings…"), agents = appMenuItem("Agent Server…");
      items.push({ separator: true },
        ...convertMenu(app, [{ ...settings, title: "Options…" }], ["Oanarina Archi Tool"]).map((x) => ({ ...x, shortcut: "Ctrl+," })),
        ...convertMenu(app, [agents], ["Oanarina Archi Tool"]));
    } else if (title === "Window") {
      items.push({ separator: true }, { title: "New Window", action: () => native ? void native.newWindow({ kind: "start" }) : void app.action("@newWindow:start") });
    } else if (title === "Help") {
      items.push({ separator: true }, ...convertMenu(app, [appMenuItem("About Oanarina Archi Tool")], ["Oanarina Archi Tool"]));
    }
    out.push({ title, items });
  }
  return out;
}

/** Run-time lists the menus show; called before a menu opens. */
export async function refreshMenuState(app: App) {
  try { menuState.recent = (await app.engine.native?.recentFiles()) ?? []; } catch { menuState.recent = []; }
}
