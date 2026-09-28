// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Windows conventions on top of the Mac layout: the Mac's ⌘ shortcuts are Ctrl here (main.ts keyboard map), plus
//   F1            help for the running (or typed) command: its section of the user guide
//                 (https://www.oanarinaldi.com/archi-tool-guide.html#<section>; the Mac's HelpPages.contextRoute)
//   Alt+letter    opens the title-bar menu with that access key (Alt+F File, Alt+E Edit, Alt+V View, Alt+D Draw, Alt+M Modify,
//                 Alt+N Annotate, Alt+A Architecture, Alt+O Model, Alt+Y Analyze, Alt+T Tools, Alt+W Window, Alt+H Help;
//                 titlebar.ts menuMnemonics), the letters underlined while Alt is held
//   Ctrl+W / Ctrl+F4   close the window · Ctrl+Shift+Z   redo (as well as Ctrl+Y) · Alt+F4   exit (native on Windows)
//   native caption buttons (snap layouts) when the main process uses titleBarOverlay (body.native-captions)
//   high-DPI: moving the window to a monitor with another scale factor re-sizes the canvases (event "archi:dpr").
import type { App } from "../app";
import ui from "../data/ui.generated.json";
import { placeAccessKeys } from "./titlebar";

export const GUIDE_URL = "https://www.oanarinaldi.com/archi-tool-guide.html";

export function openGuide(app: App, url = GUIDE_URL) {
  const n = app.engine.native;
  if (n) void n.openExternal(url);
  else window.open(url, "_blank", "noopener");
}

/**
 * The guide page for F1 (HelpPages.contextRoute on the Mac): the running command, else the command typed so far, else the
 * top of the guide. A command links to its section of the guide's command reference (anchors from docs/USER-GUIDE.md,
 * tools/gen-ui-data.mjs), else to its category's section.
 */
export function contextHelpURL(app: App): string {
  const g = (ui as any).guide ?? { commands: {}, categories: {} };
  const typed = (app.commandInput ?? "").trim().split(/\s+/)[0] ?? "";
  const name = (app.prompt?.active && app.prompt.command) ? String(app.prompt.command) : typed;
  if (!name) return GUIDE_URL;
  const def = app.lookup(name);
  const key = (def?.name ?? name).toUpperCase();
  const anchor = g.commands[key] ?? (def ? g.categories[def.category] : undefined);
  return anchor ? `${GUIDE_URL}#${anchor}` : GUIDE_URL;
}
export function openContextHelp(app: App) { openGuide(app, contextHelpURL(app)); }

export function installWindowsConventions(app: App) {
  const native = app.engine.native;
  if (native?.nativeCaptions) document.body.classList.add("native-captions");
  if (native?.platform === "win32") document.body.classList.add("win32");
  const close = () => { if (native) void native.windowControl("close"); };

  addEventListener("keydown", (e) => {
    const ctrl = e.ctrlKey || e.metaKey;
    const stop = () => { e.preventDefault(); e.stopImmediatePropagation(); };
    if (e.key === "F1" && !ctrl && !e.altKey) { stop(); openContextHelp(app); return; }
    if (e.key === "F4" && e.altKey && !ctrl) { if (!native?.nativeCaptions) { stop(); close(); } return; }
    if (e.key === "F4" && ctrl) { stop(); close(); return; }
    if (ctrl && !e.altKey && !e.shiftKey && e.code === "KeyW") { stop(); close(); return; }
    if (ctrl && !e.altKey && e.shiftKey && e.code === "KeyZ") { stop(); void app.redo(); return; }
    if (e.altKey && !ctrl && !e.shiftKey && /^Key[A-Z]$/.test(e.code)) {
      const letter = e.code.slice(3).toLowerCase();
      const btn = [...document.querySelectorAll<HTMLButtonElement>(".titlebar .menubar button")].find((b) => b.dataset.mnemonic === letter);
      if (btn) { stop(); document.body.classList.remove("alt-cues"); btn.click(); }
    }
    if (e.key === "Alt" && !ctrl) { placeAccessKeys(); document.body.classList.add("alt-cues"); }
    else if (!e.altKey) document.body.classList.remove("alt-cues");
  }, true);
  const hideCues = () => document.body.classList.remove("alt-cues");
  addEventListener("keyup", (e) => { if (e.key === "Alt") hideCues(); }, true);
  addEventListener("blur", hideCues);
  addEventListener("mousedown", hideCues, true);

  // Per-monitor DPI: devicePixelRatio changes without a CSS resize when the window moves to another display.
  let mq: MediaQueryList | null = null;
  const onChange = () => {
    watch();
    document.documentElement.dataset.dpr = String(window.devicePixelRatio || 1);
    window.dispatchEvent(new Event("archi:dpr"));
    app.canvas?.refresh();
  };
  const watch = () => {
    mq?.removeEventListener("change", onChange);
    mq = window.matchMedia(`(resolution: ${window.devicePixelRatio || 1}dppx)`);
    mq.addEventListener("change", onChange);
  };
  watch();
  document.documentElement.dataset.dpr = String(window.devicePixelRatio || 1);
}
