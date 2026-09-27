// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Custom keyboard shortcuts (KeyCombo and ShortcutDispatcher in ArchiApp/Preferences.swift) with Windows keys: Ctrl takes
// the place of ⌘, Alt of ⌥; stored normalized as "ctrl+alt+shift+w" (Mac files with cmd/opt import too), and the
// Keyboard & Mouse reference window (ShortcutsView in ArchiApp/ArchiApp.swift) with the Windows key names.
import { h } from "../dom";
import { icon } from "../icons";
import { prefs } from "../prefs";
import { toolWindow, flatButton } from "./ui";
import { app } from "./context";
import ui from "../data/ui.generated.json";

export class KeyCombo {
  constructor(public key: string, public ctrl = false, public shift = false, public alt = false) { this.key = key.toLowerCase(); }

  static readonly special: Record<string, string> = {
    Enter: "return", Tab: "tab", " ": "space", Backspace: "delete", Delete: "del", Escape: "escape", ArrowLeft: "left", ArrowRight: "right", ArrowDown: "down", ArrowUp: "up",
    Home: "home", End: "end", PageUp: "pageup", PageDown: "pagedown", Insert: "insert",
  };

  /** From a keydown event (the key without Shift, like charactersIgnoringModifiers). Nil for modifier-only presses. */
  static fromEvent(e: KeyboardEvent): KeyCombo | null {
    if (["Control", "Shift", "Alt", "Meta", "AltGraph", "CapsLock"].includes(e.key)) return null;
    let k: string;
    if (/^F\d{1,2}$/.test(e.key)) k = e.key.toLowerCase();
    else if (KeyCombo.special[e.key]) k = KeyCombo.special[e.key];
    else if (/^Key[A-Z]$/.test(e.code)) k = e.code.slice(3).toLowerCase();
    else if (/^Digit\d$/.test(e.code)) k = e.code.slice(5);
    else if (e.code === "Equal") k = "="; else if (e.code === "Minus") k = "-"; else if (e.code === "Comma") k = ","; else if (e.code === "Period") k = ".";
    else if (e.code === "Slash") k = "/"; else if (e.code === "Semicolon") k = ";"; else if (e.code === "BracketLeft") k = "["; else if (e.code === "BracketRight") k = "]";
    else if (e.key.length === 1) k = e.key.toLowerCase();
    else return null;
    return new KeyCombo(k, e.ctrlKey || e.metaKey, e.shiftKey, e.altKey);
  }

  /** Parses "ctrl+shift+w", "Ctrl+Shift+W", "shift+cmd+w", "⇧⌘W" (⌘ = Ctrl, ⌥ = Alt, ⌃ = Ctrl). */
  static parse(text: string): KeyCombo | null {
    let t = text.toLowerCase().replace(/ /g, "");
    let c = false, s = false, a = false;
    for (const [sym, f] of [["⌘", "c"], ["⇧", "s"], ["⌥", "a"], ["⌃", "c"]] as const) {
      if (t.includes(sym)) { t = t.split(sym).join(""); if (f === "c") c = true; else if (f === "s") s = true; else a = true; }
    }
    const parts = t.split(/[+-](?=.)/);
    const last = parts.pop();
    if (!last) return null;
    for (const p of parts) {
      if (p === "cmd" || p === "command" || p === "ctrl" || p === "control") c = true;
      else if (p === "shift") s = true;
      else if (p === "opt" || p === "option" || p === "alt") a = true;
      else if (p !== "") return null;
    }
    return new KeyCombo(last, c, s, a);
  }

  get normalized(): string {
    const p: string[] = [];
    if (this.ctrl) p.push("ctrl");
    if (this.alt) p.push("alt");
    if (this.shift) p.push("shift");
    p.push(this.key);
    return p.join("+");
  }
  toString(): string {
    const p: string[] = [];
    if (this.ctrl) p.push("Ctrl");
    if (this.alt) p.push("Alt");
    if (this.shift) p.push("Shift");
    p.push(this.key.length === 1 ? this.key.toUpperCase() : this.key[0].toUpperCase() + this.key.slice(1));
    return p.join("+");
  }
  /** A shortcut must use Ctrl (or be a function key) so typing on the command line keeps working. */
  get isAssignable(): boolean { return this.ctrl || /^f\d{1,2}$/.test(this.key); }
}

/** The app's own shortcuts; a custom shortcut with the same keys replaces them (the user is warned). */
export const RESERVED: Record<string, string> = {
  "ctrl+n": "New", "ctrl+o": "Open", "ctrl+s": "Save", "ctrl+shift+s": "Save As", "ctrl+w": "Close", "ctrl+p": "Plot", "ctrl+shift+p": "Page Setup",
  "ctrl+z": "Undo", "ctrl+y": "Redo", "ctrl+shift+z": "Redo", "ctrl+x": "Cut", "ctrl+c": "Copy", "ctrl+v": "Paste", "ctrl+a": "Select All", "ctrl+shift+a": "Deselect All",
  "ctrl+k": "Search Commands", "ctrl+=": "Zoom In", "ctrl+-": "Zoom Out", "ctrl+alt+p": "Show/Hide Panels", "ctrl+alt+j": "Script Console", "ctrl+,": "Settings",
  "ctrl+shift+i": "Import", "ctrl+alt+shift+p": "Plot Preview", "ctrl+alt+1": "2D Plan", "ctrl+alt+2": "3D Model", "ctrl+alt+3": "Split View", "ctrl+alt+4": "Sheets",
  "ctrl+0": "Clean Screen", "ctrl+shift+/": "Command Reference",
};

/** Custom shortcuts as stored (normalized key → command line). Mac-style keys from an import are normalized. */
export function shortcutMap(): Record<string, string> { return prefs.get("shortcuts"); }

/** Runs a user-assigned shortcut (ShortcutDispatcher.handle). True when the event was consumed. */
export function dispatchShortcut(e: KeyboardEvent): boolean {
  const map = shortcutMap();
  if (!Object.keys(map).length) return false;
  const c = KeyCombo.fromEvent(e);
  if (!c) return false;
  const line = map[c.normalized];
  if (!line) return false;
  e.preventDefault();
  void app().runCommand(line);
  return true;
}

/** Windows key text for a Mac shortcut (docs/windows-parity.json shortcuts, else ⌘ → Ctrl, ⌥ → Alt, ⇧ → Shift). */
export function windowsKeys(mac: string): string {
  const list = ((ui as any).shortcuts ?? []) as { mac: string; windows: string | null; keys: string }[];
  const hit = list.find((s) => s.mac === mac && s.windows);
  if (hit) return hit.windows!.replace(/ → .*$/, "").replace(/\?$/, "");
  return mac.replace(/⌥⇧⌘/g, "Ctrl+Alt+Shift+").replace(/⌥⌘/g, "Ctrl+Alt+").replace(/⇧⌘/g, "Ctrl+Shift+").replace(/⌘/g, "Ctrl+").replace(/⌃/g, "Ctrl+").replace(/⌥/g, "Alt+").replace(/⇧/g, "Shift+").replace(/^Delete$/, "Del");
}

const REFERENCE: [string, string][] = [
  ["Type anywhere", "Start a command on the command line"],
  ["Enter / Space", "Finish input · repeat the last command"],
  ["Esc", "Cancel the command · clear the selection"],
  ["Right-click", "Enter while a command runs · context menu when idle"],
  ["Tab", "Accept autocomplete"], ["↑ / ↓", "Command history / suggestions"],
  ["F1", "Help for the running command"], ["F2", "Command history panel"], ["F3", "Object snap on/off"], ["F7", "Grid display"], ["F8", "Ortho mode"], ["F9", "Grid snap"], ["F10", "Polar tracking"], ["F11", "Object snap tracking"], ["F12", "Dynamic input"],
  ["Scroll wheel / pinch", "Zoom about the cursor"], ["Two-finger scroll", "Pan"], ["Middle-drag · Space+drag", "Pan"],
  ["Double middle-click", "Zoom extents"], ["⌘0", "Zoom extents"], ["⌘= / ⌘-", "Zoom in / out"],
  ["Drag left → right", "Window selection (fully inside)"], ["Drag right → left", "Crossing selection (touching)"],
  ["Shift-click", "Toggle an object in the selection"], ["Click a grip", "Stretch the object (wall ends move joined walls)"],
  ["Double-click text", "Edit text"], ["Delete", "Erase the selection"],
  ["⌘Z / ⇧⌘Z", "Undo / Redo"], ["⌘C / ⌘X / ⌘V", "Copy / Cut / Paste objects (paste at cursor)"], ["⌘A", "Select all"],
  ["⌥⌘1 … ⌥⌘4", "2D · 3D · Split · Sheets"], ["⌥⌘P", "Show / hide panels"], ["⌥⌘J", "Script console"],
  ["⌘N / ⌘O / ⌘S / ⇧⌘S", "New · Open · Save · Save As"], ["⌘P", "Plot / Print"], ["⇧⌘P", "Page setup"], ["⌥⇧⌘P", "Plot preview"],
  ["⌘K", "Search commands"], ["⌃0", "Clean screen"], ["⌘,", "Settings (custom shortcuts, colors, autosave…)"], ["⇧⌘/", "Command reference"],
];

/** Rows of the Keyboard & Mouse window with Windows keys (parity table; a mapped-away key such as ⌘0 is dropped). */
export function referenceRows(): [string, string][] {
  const list = ((ui as any).shortcuts ?? []) as { mac: string; windows: string | null; action: string }[];
  const out: [string, string][] = [];
  for (const [k, v] of REFERENCE) {
    const hit = list.find((s) => s.mac === k && s.action.includes(v));
    if (hit && hit.windows === null) continue;
    let key = hit?.windows ? hit.windows.replace(/ → .*$/, "") : windowsKeys(k);
    if (/\(none\)/.test(key)) continue;
    key = key.replace(/\?$/, "");
    if (out.some(([a, b]) => a === key && b === v)) continue;
    out.push([key, v]);
  }
  return out;
}

/** Help ▸ Keyboard Shortcuts (ShortcutsView): the keyboard and mouse reference. */
export function openShortcutsReference() {
  toolWindow("keyboard-shortcuts", "Keyboard Shortcuts", 560, 520, (body, w) => {
    const head = h("div", { class: "dlg-title", style: { padding: "12px" } }, icon("keyboard", 14), h("span", { text: "Keyboard & Mouse", style: { fontSize: "14px" } }), h("span", { class: "spacer" }),
      flatButton("Done", () => w.close(), { prominent: true }));
    const grid = h("div", { class: "kbd-grid" });
    for (const [k, v] of referenceRows()) grid.append(h("div", { class: "k", text: k }), h("div", { text: v }));
    body.style.flexDirection = "column";
    body.append(head, h("div", { class: "hsep" }), grid);
  });
}
