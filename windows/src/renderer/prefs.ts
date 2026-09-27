// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Application preferences (Settings / OPTIONS), the Windows counterpart of AppPreferences in ArchiApp/Preferences.swift:
// same keys, defaults and ranges, persisted in the renderer's localStorage (shared by every window of the app and
// kept in step with the `storage` event) and applied without restart (theme, accent, canvas colour, crosshair).

export type Theme = "dark" | "light";
export interface DraftDefaults {
  showGrid: boolean; gridSnap: boolean; gridSpacing: number; ortho: boolean; polarTracking: boolean; polarIncrement: number;
  dynamicInput: boolean; lineweightDisplay: boolean; objectSnap: boolean; snapModes: string[];
}
export interface WorkspaceLayout {
  name: string; mode: string; showPanels: boolean; panelTab: string; showScriptConsole: boolean; ribbonTab: string; ribbonCollapsed: boolean; cleanScreen: boolean;
}
export interface CustomRibbonPanel { id: string; title: string; tab: string; commands: string[]; symbols: Record<string, string> }
export interface RibbonCustomization { format: string; version: number; panels: CustomRibbonPanel[]; hiddenPanels: string[]; quickAccess?: string[] }

/** SnapKind.allCases (ArchiCore/Commands/Editor.swift). */
export const SNAP_KINDS = ["endpoint", "midpoint", "center", "node", "quadrant", "intersection", "extension", "insertion", "perpendicular", "tangent", "nearest", "parallel", "grid"];
/** DraftSettings() defaults. */
export const DEFAULT_DRAFT: DraftDefaults = {
  showGrid: true, gridSnap: false, gridSpacing: 100, ortho: false, polarTracking: true, polarIncrement: 45, dynamicInput: true, lineweightDisplay: true,
  objectSnap: true, snapModes: ["endpoint", "midpoint", "center", "intersection", "perpendicular", "quadrant", "node", "insertion"],
};
export const DEFAULT_ACCENT = "#F5C518";
export const DEFAULT_CANVAS = "#1E1F22";
export const DEFAULT_QUICK_ACCESS = ["NEW", "OPEN", "SAVE", "UNDO", "REDO", "PLOT"];
export const ACCENT_PRESETS: [string, string][] = [["Archi Yellow", "#F5C518"], ["Orange", "#FF8A3D"], ["Red", "#E5534B"], ["Pink", "#E86FB0"],
  ["Purple", "#A27BF0"], ["Blue", "#4C9AFF"], ["Teal", "#2EC4B6"], ["Green", "#5CC96B"]];
export const CANVAS_PRESETS: [string, string][] = [["Graphite", "#1E1F22"], ["Black", "#000000"], ["Model Blue", "#21283A"], ["Slate", "#2B2F36"], ["Dark Green", "#1C2620"]];
export const UNITS = ["millimeters", "centimeters", "meters", "inches", "feet"];
export const UNIT_ABBR: Record<string, string> = { millimeters: "mm", centimeters: "cm", meters: "m", inches: "in", feet: "ft" };
export const RIBBON_TABS = ["Home", "Insert", "Annotate", "Architecture", "Modeling", "Analyze", "Collaborate", "View", "Output", "Manage", "Script"];

/** WorkspaceLayout.builtIn (ArchiApp/Workspaces.swift). Modes use the Windows names (2D, 3D, Split, Sheet). */
export const BUILTIN_WORKSPACES: WorkspaceLayout[] = [
  { name: "Drafting & Annotation", mode: "2D", showPanels: true, panelTab: "Properties", showScriptConsole: false, ribbonTab: "Home", ribbonCollapsed: false, cleanScreen: false },
  { name: "Building Design", mode: "Split", showPanels: true, panelTab: "Levels", showScriptConsole: false, ribbonTab: "Architecture", ribbonCollapsed: false, cleanScreen: false },
  { name: "3D Modeling", mode: "3D", showPanels: true, panelTab: "Materials", showScriptConsole: false, ribbonTab: "View", ribbonCollapsed: false, cleanScreen: false },
  { name: "Sheets & Plotting", mode: "Sheet", showPanels: true, panelTab: "Browser", showScriptConsole: false, ribbonTab: "Output", ribbonCollapsed: false, cleanScreen: false },
  { name: "Scripting", mode: "2D", showPanels: true, panelTab: "History", showScriptConsole: true, ribbonTab: "Script", ribbonCollapsed: false, cleanScreen: false },
];

const DEFAULTS = {
  accentHex: DEFAULT_ACCENT, canvasHex: DEFAULT_CANVAS, theme: "dark" as Theme, cursorSize: 10,
  autosaveMinutes: 5, recentLimit: 12, runStartupScript: true, crashReports: false,
  templatesFolder: "", scriptsFolder: "", exportFolder: "",
  defaultUnits: "millimeters", draft: DEFAULT_DRAFT,
  shortcuts: {} as Record<string, string>, quickAccess: DEFAULT_QUICK_ACCESS, hiddenRibbonTabs: [] as string[],
  agentPort: 47800, agentAutoStart: false,
  ribbonCustomization: { format: "oanarina-archi-cui", version: 1, panels: [], hiddenPanels: [] } as RibbonCustomization,
  workspacesCustom: [] as WorkspaceLayout[], workspaceCurrent: "Drafting & Annotation", recentTemplates: [] as string[],
};
export type PrefKey = keyof typeof DEFAULTS;
type Prefs = { -readonly [K in PrefKey]: (typeof DEFAULTS)[K] };

const PREFIX = "archi.pref.";
function read<K extends PrefKey>(k: K): Prefs[K] {
  try {
    const v = localStorage.getItem(PREFIX + k);
    if (v === null) return clone(DEFAULTS[k]) as Prefs[K];
    const parsed = JSON.parse(v);
    if (k === "draft") return { ...DEFAULT_DRAFT, ...parsed } as Prefs[K];
    return parsed;
  } catch { return clone(DEFAULTS[k]) as Prefs[K]; }
}
function clone<T>(v: T): T { return v !== null && typeof v === "object" ? JSON.parse(JSON.stringify(v)) : v; }

class Preferences {
  private listeners = new Set<(key: PrefKey | "*") => void>();
  private cache = new Map<PrefKey, unknown>();

  constructor() {
    try { addEventListener("storage", (e) => { if (e.key?.startsWith(PREFIX)) { this.cache.delete(e.key.slice(PREFIX.length) as PrefKey); this.changed(e.key.slice(PREFIX.length) as PrefKey); } }); } catch {}
  }
  get<K extends PrefKey>(k: K): Prefs[K] {
    if (!this.cache.has(k)) this.cache.set(k, read(k));
    return clone(this.cache.get(k)) as Prefs[K];
  }
  set<K extends PrefKey>(k: K, v: Prefs[K]) {
    this.cache.set(k, clone(v));
    try { localStorage.setItem(PREFIX + k, JSON.stringify(v)); } catch {}
    this.changed(k);
  }
  /** Restores every preference to its default (Reset to Defaults). */
  resetToDefaults() {
    for (const k of Object.keys(DEFAULTS) as PrefKey[]) {
      if (k === "workspacesCustom" || k === "workspaceCurrent" || k === "recentTemplates" || k === "ribbonCustomization" || k === "crashReports") continue;
      this.cache.set(k, clone(DEFAULTS[k]));
      try { localStorage.removeItem(PREFIX + k); } catch {}
    }
    this.changed("*");
  }
  on(cb: (key: PrefKey | "*") => void) { this.listeners.add(cb); return () => this.listeners.delete(cb); }
  private changed(k: PrefKey | "*") { applyTheme(); this.listeners.forEach((cb) => cb(k)); }

  // Convenience accessors.
  get accent() { return this.get("accentHex"); }
  get canvasColor() { return this.get("canvasHex"); }
  get light() { return this.get("theme") === "light"; }
  get cursorSize() { return Math.min(100, Math.max(1, Math.round(Number(this.get("cursorSize")) || 10))); }
  get quickAccess() { return this.get("quickAccess"); }
  get hiddenRibbonTabs() { return this.get("hiddenRibbonTabs"); }
  get ribbon(): RibbonCustomization {
    const r: Partial<RibbonCustomization> = this.get("ribbonCustomization") ?? {};
    return { format: "oanarina-archi-cui", version: r.version ?? 1, panels: r.panels ?? [], hiddenPanels: r.hiddenPanels ?? [] };
  }

  /** Workspaces.all: built-in ones not replaced by a custom one of the same name, then the custom ones. */
  get workspaces(): WorkspaceLayout[] {
    const c = this.get("workspacesCustom");
    return [...BUILTIN_WORKSPACES.filter((b) => !c.some((w) => w.name.toLowerCase() === b.name.toLowerCase())), ...c];
  }
  findWorkspace(name: string): WorkspaceLayout | undefined {
    const n = name.trim(), all = this.workspaces;
    return all.find((w) => w.name.toLowerCase() === n.toLowerCase()) ?? (n ? all.find((w) => w.name.toLowerCase().startsWith(n.toLowerCase())) : undefined);
  }
  saveWorkspace(w: WorkspaceLayout) {
    const c = this.get("workspacesCustom").filter((x) => x.name.toLowerCase() !== w.name.toLowerCase());
    c.push(w);
    this.set("workspacesCustom", c);
    this.set("workspaceCurrent", w.name);
  }
  deleteWorkspace(name: string) { this.set("workspacesCustom", this.get("workspacesCustom").filter((x) => x.name.toLowerCase() !== name.toLowerCase())); }

  /** Recently used template files (most recent first, at most 8). */
  noteTemplateUsed(path: string) {
    const l = this.get("recentTemplates").filter((p) => p !== path);
    l.unshift(path);
    this.set("recentTemplates", l.slice(0, 8));
  }
}

export const prefs = new Preferences();

// ---- theme (Theme.swift colours) ----
const LIGHT: Record<string, string> = {
  "--panel": "#F2F2F4", "--ribbon": "#E9E9EC", "--tabbar": "#DADADF", "--field": "#FFFFFF", "--hover": "rgba(0,0,0,0.07)", "--pressed": "rgba(0,0,0,0.12)",
  "--sep": "rgba(0,0,0,0.12)", "--text": "#1D1D20", "--dim": "#5E5F66", "--faint": "#9A9BA1", "--menu": "#FFFFFF", "--titlebar": "#E3E3E7",
};
function hexToRgb(hex: string): [number, number, number] {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim());
  const n = m ? parseInt(m[1], 16) : 0xF5C518;
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
let sentTheme = "";
export function applyTheme() {
  const root = document.documentElement;
  if (!root) return;
  const light = prefs.light;
  root.dataset.theme = light ? "light" : "dark";
  // Windows: native dialogs, scroll bars and the title bar caption buttons follow the theme (src/main/main.ts window:theme).
  if (sentTheme !== root.dataset.theme) { sentTheme = root.dataset.theme; try { (globalThis as any).archi?.setTheme?.(sentTheme); } catch {} }
  for (const [k, v] of Object.entries(LIGHT)) { if (light) root.style.setProperty(k, v); else root.style.removeProperty(k); }
  const acc = prefs.accent;
  root.style.setProperty("--accent", acc);
  const [r, g, b] = hexToRgb(acc);
  root.style.setProperty("--accent-rgb", `${r},${g},${b}`);
  root.style.setProperty("--canvas", prefs.canvasColor);
}
export { hexToRgb };
