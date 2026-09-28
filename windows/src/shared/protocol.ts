// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Engine protocol types (newline-delimited JSON-RPC 2.0 over archi-engine's stdin/stdout). See docs/WINDOWS-PORT.md.

export type Vec = [number, number];

export interface CommandInfo { name: string; aliases: string[]; category: string; summary: string }
export interface SysvarInfo { name: string; kind?: string; default?: string; range?: string; summary?: string }
export interface Hello { name?: string; version: string; protocol?: string; platform?: string; methods?: string[]; commands: CommandInfo[]; sysvars: SysvarInfo[] | Record<string, string | number | boolean> }

export interface LevelInfo { id?: number; name: string; elevation: number; height: number }
export interface DocInfo {
  title: string; path?: string | null; dirty: boolean; units: string;
  levels: LevelInfo[]; currentLevel: string; layouts: string[]; extents: [number, number, number, number];
  unitAbbreviation?: string; currentLevelId?: number; empty?: boolean; project?: string; currentLayer?: string; entities?: number; elements?: number; canUndo?: boolean; canRedo?: boolean;
}

/** Snap marker: `point` per docs/ENGINE-PROTOCOL.md (x/y accepted too). */
export interface SnapInfo { kind: string; point?: Vec; x?: number; y?: number; entity?: number | string }
export function snapPoint(s: SnapInfo): Vec { return s.point ? [s.point[0], s.point[1]] : [Number(s.x), Number(s.y)]; }
export interface PromptState {
  /** message = the command-line prompt as the Mac shows it ("Specify next point [Undo]:"); label = without keywords/default. */
  active: boolean; command?: string; message: string; label?: string; keywords: string[]; kinds: string[];
  transparent?: boolean; rotatable?: boolean; cursor?: Vec | null; hover?: unknown;
  defaultValue?: string; preview: unknown[];
  /** Optional extensions the shell uses when the engine sends them. */
  base?: Vec | { x: number; y: number } | null;
  snap?: SnapInfo | null;
  tracking?: { points?: Vec[]; lines?: { from: Vec; to: Vec }[] } | null;
}

export interface Selection { ids: string[]; summary: string; types?: { type: string; count: number }[] }
export interface Grip { id: string | number; index: number; x: number; y: number; kind?: string }

export interface Notification { method: string; params: any }

/** Bridge exposed by the preload script as window.archi. */
export interface ArchiBridge {
  rpc(method: string, params?: unknown): Promise<any>;
  onNotify(cb: (n: Notification) => void): void;
  platform: string;
  windowControl(action: "minimize" | "maximize" | "close" | "isMaximized" | "quit" | "fullscreen"): Promise<boolean>;
  onWindowState(cb: (s: { maximized: boolean; focused: boolean }) => void): void;
  openFileDialog(opts: { title?: string; filters?: { name: string; extensions: string[] }[] }): Promise<string | null>;
  saveFileDialog(opts: { title?: string; defaultPath?: string; filters?: { name: string; extensions: string[] }[] }): Promise<string | null>;
  recentFiles(): Promise<{ path: string; modified?: number }[]>;
  addRecent(path: string): Promise<void>;
  clearRecent(): Promise<void>;
  samplePath(name: string): Promise<string | null>;
  newWindow(request?: { kind: string; path?: string }): Promise<void>;
  initialRequest(): Promise<{ kind: string; path?: string } | null>;
  openExternal(url: string): Promise<void>;
  setTitle(title: string): void;
  /** Windows: the title bar uses the native caption buttons (titleBarOverlay); the shell hides its own. */
  nativeCaptions?: boolean;
  /** Settings ▸ Appearance changed: native dialogs, scroll bars and the caption buttons follow the theme. */
  setTheme?(theme: "dark" | "light"): void;
  fileUrl(path: string): string;
  // Settings and dialogs (src/main/settings-ipc.ts): standard folders, reveal/choose folders, text files.
  paths?(): Promise<{ userData: string; documents: string; home: string; desktop: string; templates: string; scripts: string; recovery: string }>;
  setSetting?(key: string, value: unknown): Promise<void>;
  revealPath?(path: string): Promise<void>;
  chooseFolder?(opts: { title?: string; defaultPath?: string }): Promise<string | null>;
  readTextFile?(path: string): Promise<string | null>;
  writeTextFile?(path: string, text: string): Promise<boolean>;
  removeFile?(path: string): Promise<void>;
}
