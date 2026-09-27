// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Windows conventions on top of the Mac layout: the Mac's ⌘ shortcuts are Ctrl here (main.ts keyboard map), plus
//   F1            the user guide (https://www.oanarinaldi.com/archi-tool-guide.html; the Mac's Help ▸ User Guide)
//   Alt+letter    opens the title-bar menu starting with that letter (Alt+F File, Alt+E Edit, Alt+V View, Alt+H Help …)
//   Ctrl+W / Ctrl+F4   close the window · Ctrl+Shift+Z   redo (as well as Ctrl+Y) · Alt+F4   exit (native on Windows)
//   native caption buttons (snap layouts) when the main process uses titleBarOverlay (body.native-captions)
//   high-DPI: moving the window to a monitor with another scale factor re-sizes the canvases (event "archi:dpr").
import type { App } from "../app";

export const GUIDE_URL = "https://www.oanarinaldi.com/archi-tool-guide.html";

export function openGuide(app: App) {
  const n = app.engine.native;
  if (n) void n.openExternal(GUIDE_URL);
  else window.open(GUIDE_URL, "_blank", "noopener");
}

export function installWindowsConventions(app: App) {
  const native = app.engine.native;
  if (native?.nativeCaptions) document.body.classList.add("native-captions");
  if (native?.platform === "win32") document.body.classList.add("win32");
  const close = () => { if (native) void native.windowControl("close"); };

  addEventListener("keydown", (e) => {
    const ctrl = e.ctrlKey || e.metaKey;
    const stop = () => { e.preventDefault(); e.stopImmediatePropagation(); };
    if (e.key === "F1" && !ctrl && !e.altKey) { stop(); openGuide(app); return; }
    if (e.key === "F4" && e.altKey && !ctrl) { if (!native?.nativeCaptions) { stop(); close(); } return; }
    if (e.key === "F4" && ctrl) { stop(); close(); return; }
    if (ctrl && !e.altKey && !e.shiftKey && e.code === "KeyW") { stop(); close(); return; }
    if (ctrl && !e.altKey && e.shiftKey && e.code === "KeyZ") { stop(); void app.redo(); return; }
    if (e.altKey && !ctrl && !e.shiftKey && /^Key[A-Z]$/.test(e.code)) {
      const letter = e.code.slice(3).toLowerCase();
      const btn = [...document.querySelectorAll<HTMLButtonElement>(".titlebar .menubar button")].find((b) => (b.textContent ?? "").trim().toLowerCase().startsWith(letter));
      if (btn) { stop(); btn.click(); }
    }
  }, true);

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
