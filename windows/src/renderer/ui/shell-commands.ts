// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// One way to run a menu, ribbon or keyboard entry, like the Mac's menu buttons: an entry with a Mac `ui` target opens
// that window, "@…" entries are shell actions (app.action), commands the shell implements itself (the Mac runs them in
// its UI layer: About, command search, clean screen, the Block Library and Family Editor windows, Open / Save …) run
// here, everything else goes to the engine's command line. Typed commands always go to the engine; the engine's
// portable versions of these commands answer with `host` notifications (docs/ENGINE-PROTOCOL.md).
import type { App } from "../app";

export type ShellHandler = (app: App) => void | Promise<void>;
const handlers = new Map<string, ShellHandler>();

/** Registers a shell implementation for command names (the Mac UI-layer command of the same name). */
export function registerShellCommand(names: string[], fn: ShellHandler) { for (const n of names) handlers.set(n.toUpperCase(), fn); }
export function shellCommand(name: string | undefined): ShellHandler | undefined { return name && !/\s/.test(name.trim()) ? handlers.get(name.trim().toUpperCase()) : undefined; }

export interface Runnable { command?: string; args?: string; ui?: string; names?: string[] }

/** The line an entry runs: the first of its names the engine knows, a shell command, or an "@" action; null = disabled. */
export function resolveEntry(app: App, it: Runnable): string | null {
  const c = it.command?.trim();
  if (!c) return null;
  if (c.startsWith("@")) return c;
  if (!it.args && shellCommand(c)) return c;
  for (const n of [c, ...(it.names ?? [])]) if (app.has(n.split(" ")[0])) return n;
  return null;
}

/** True when the entry can run (a `ui` target the shell opens, a known command or a shell action). */
export function entryEnabled(app: App, it: Runnable): boolean { return !!resolveEntry(app, it) || (!!it.ui && uiKnown(it.ui)); }

/** Mac `ui` targets the Windows shell implements (the part A/B/output hooks answer the rest at run time). */
const UI_TARGETS = /^(window:(PreferencesWindow|PreferencesWindow\.\w+|keyboard-shortcuts|CUIWindow|BlockLibraryWindow|MaterialLibraryWindow|NodeEditorWindow|MarkupWindow|CompareWindow|RevisionCloudWindow|AboutWindow|command-reference)|sheet:(units|drafting|quickSelect|layerStates|pageSetup|titleBlock|connectClaude))$/;
export function uiKnown(ref: string) { return UI_TARGETS.test(ref); }

export async function runEntry(app: App, it: Runnable, resolved: string | null = resolveEntry(app, it)): Promise<void> {
  if (it.ui && app.uiHooks.ui?.(it.ui)) return;
  if (!resolved) return;
  if (resolved.startsWith("@")) return app.action(resolved);
  const h = !it.args ? shellCommand(resolved) : undefined;
  if (h) return h(app);
  return app.runCommand(it.args ? `${resolved} ${it.args}` : resolved);
}
