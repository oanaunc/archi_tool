// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The Mac app's keyboard shortcuts with Windows keys (⌘ → Ctrl, ⌥ → Alt, ⇧ → Shift), from the menu items and the
// Keyboard & Mouse window (docs/windows-parity.json "shortcuts"), with the Windows conflicts resolved as documented
// there: Redo is Ctrl+Y (Ctrl+Shift+Z kept), Ctrl+0 is Clean Screen so Zoom Extents has no Ctrl key, Ctrl+Q / Ctrl+H /
// Ctrl+M / Ctrl+F (quit, hide, minimise, full screen) are not bound, Alt+F4 and Ctrl+F4 close the window. F1 is
// help for the running command, F2 the history panel, F3 and F7-F12 the drafting toggles.
// Every modifier counts: Ctrl+Alt+P (panels) ≠ Ctrl+Alt+Shift+P (plot preview) ≠ Ctrl+P (plot), Ctrl+Shift+A deselects.
// AltGr: on European layouts Ctrl+Alt is AltGr and types characters (@ € { …); a Ctrl+Alt press that produces a
// character other than the key's own letter or digit is typing, not a shortcut (see altGrCharacter).
import type { App } from "../app";
import ui from "../data/ui.generated.json";
import { KeyCombo } from "../dialogs/shortcuts";
import { runEntry, Runnable } from "./shell-commands";

export interface Binding extends Runnable { keys: string; title: string }

/** Windows key text for a Mac menu path, from the catalogue ("(none)" / null = not bound on Windows). */
function windowsKeys(s: any): string | null {
  const w = s.windows === undefined ? s.keys : s.windows;
  if (!w || w === "(none)" || /\?$/.test(w) || w === "Alt+F4") return null;
  return w;
}

/** The catalogue menu item at a path such as "File ▸ Page Setup…" (for its `ui` target and names). */
export function menuItemAt(pathText: string): any | null {
  const parts = pathText.split(" ▸ ");
  let items: any[] = ((ui as any).menus ?? []).map((m: any) => ({ title: m.title, items: m.items }));
  let found: any = null;
  for (const p of parts) {
    found = items.find((i) => i.title === p);
    if (!found) return null;
    items = found.submenu ?? found.items ?? [];
  }
  return found;
}

function buildBindings(): Binding[] {
  const out: Binding[] = [];
  const seen = new Set<string>();
  const add = (keys: string, title: string, it: Runnable) => {
    for (const k of keys.split(" / ")) {
      const c = KeyCombo.parse(k.trim());
      if (!c || seen.has(c.normalized)) continue;
      seen.add(c.normalized);
      out.push({ keys: c.normalized, title, ...it });
    }
  };
  // Windows conventions first (they win over a Mac key with the same Windows spelling).
  add("Ctrl+Y", "Redo", { command: "REDO" });
  add("Ctrl+0", "Clean Screen", { command: "@cleanScreen" });
  for (const s of ((ui as any).shortcuts ?? []) as any[]) {
    if (s.source !== "menu" || !s.command) continue;
    const keys = windowsKeys(s);
    if (!keys) continue;
    const it = menuItemAt(s.action) ?? {};
    add(keys, String(s.action).split(" ▸ ").pop()!, { command: s.command, ui: it.ui, names: it.names });
    if (s.command === "REDO") add(s.keys, "Redo", { command: "REDO" }); // Ctrl+Shift+Z kept as a second binding
  }
  // Zoom keys on the numeric keypad and Ctrl++ (Shift+= on US keyboards).
  add("Ctrl+Shift+=", "Zoom In", { command: "@zoom:in" });
  add("Ctrl++", "Zoom In", { command: "@zoom:in" });
  // Keyboard & Mouse window: F2 opens the command history panel (F1 is in windows-conventions.ts).
  add("F2", "Command history panel", { command: "@panel:History" });
  return out;
}

export const BINDINGS: Binding[] = buildBindings();
const byKeys = new Map(BINDINGS.map((b) => [b.keys, b]));

/** Menu label for a Mac menu entry: its Windows key(s) ("Ctrl+Y" for Redo, nothing for Zoom Extents). */
export function shortcutLabel(it: { command?: string; args?: string }, menuPath: string): string | undefined {
  const s = ((ui as any).shortcuts ?? []).find((x: any) => x.source === "menu" && x.action === menuPath);
  if (s) { const k = windowsKeys(s); return k ? (KeyCombo.parse(k)?.toString() ?? k) : undefined; }
  if (it.command === "@cleanScreen") return "Ctrl+0";
  return undefined;
}

/** A Ctrl+Alt press that types a character (AltGr on European layouts: AltGr+Q = @, AltGr+E = € …). */
export function altGrCharacter(e: KeyboardEvent): boolean {
  if (e.getModifierState?.("AltGraph")) return e.key.length === 1;
  if (!(e.ctrlKey && e.altKey) || e.key.length !== 1) return false;
  if (/^Key[A-Z]$/.test(e.code)) return e.key.toLowerCase() !== e.code.slice(3).toLowerCase();
  if (/^Digit\d$/.test(e.code)) return e.key !== e.code.slice(5);
  return true;
}

const NUMPAD: Record<string, string> = { NumpadAdd: "+", NumpadSubtract: "-", NumpadEqual: "=", NumpadDivide: "/", NumpadMultiply: "*" };
/** Normalized combos of a key event: by physical key (layout independent) and by the character typed. */
export function eventCombos(e: KeyboardEvent): string[] {
  const out: string[] = [];
  const c = KeyCombo.fromEvent(e);
  if (c) out.push(c.normalized);
  const np = NUMPAD[e.code] ?? (/^Numpad\d$/.test(e.code) ? e.code.slice(6) : undefined);
  const mods = (k: string, shift: boolean) => new KeyCombo(k, e.ctrlKey || e.metaKey, shift, e.altKey).normalized;
  if (np) out.push(mods(np, e.shiftKey));
  if (e.key.length === 1) {
    out.push(mods(e.key.toLowerCase(), e.shiftKey));
    if (e.shiftKey && !/[a-z0-9]/i.test(e.key)) out.push(mods(e.key, false)); // "?" typed with Shift: Ctrl+? as well
  }
  return [...new Set(out)];
}

export function bindingFor(e: KeyboardEvent): Binding | null {
  if (altGrCharacter(e)) return null;
  for (const k of eventCombos(e)) { const b = byKeys.get(k); if (b) return b; }
  return null;
}

const TEXT_EDIT = new Set(["ctrl+a", "ctrl+c", "ctrl+x", "ctrl+v", "ctrl+z", "ctrl+y", "ctrl+shift+z"]);
/**
 * Handles a keydown for the main window. `inText`: the command line has text, so Ctrl+A/C/X/V/Z/Y edit that text.
 * True when the key was a shortcut.
 */
export function handleShortcut(app: App, e: KeyboardEvent, inText = false): boolean {
  const b = bindingFor(e);
  if (!b) return false;
  if (inText && TEXT_EDIT.has(b.keys)) return false;
  e.preventDefault();
  void runEntry(app, b);
  return true;
}
