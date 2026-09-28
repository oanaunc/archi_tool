// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// window.archiWS (preload/workspace.ts) with browser fallbacks for the web build and tests: one window, settings in a
// downloaded JSON file, crash-report state in localStorage, no network for the assistant.
export interface WinInfo { id: number; title: string; path: string | null; dirty: boolean; focused: boolean; tabbed: boolean; summary?: string }

const W = (): any => (window as any).archiWS ?? null;
export const isElectron = () => !!W();

let webState: WinInfo = { id: 1, title: "Untitled", path: null, dirty: false, focused: true, tabbed: false };
const webListeners: ((l: WinInfo[]) => void)[] = [];
function lsGet(k: string, d: string) { try { return localStorage.getItem(k) ?? d; } catch { return d; } }
function lsSet(k: string, v: string) { try { localStorage.setItem(k, v); } catch {} }

export const WS = {
  setState(s: { title: string; path: string | null; dirty: boolean; summary?: string }) {
    const w = W();
    if (w) { w.setState(s); return; }
    webState = { ...webState, ...s };
    webListeners.forEach((cb) => cb([webState]));
  },
  async windows(): Promise<WinInfo[]> { const w = W(); return w ? w.windows() : [webState]; },
  onWindows(cb: (l: WinInfo[]) => void) { const w = W(); if (w) w.onWindows(cb); else webListeners.push(cb); },
  async focus(id: number) { const w = W(); return w ? w.focus(id) : true; },
  async close(id: number) { const w = W(); if (w) await w.close(id); },
  async arrange(mode: string): Promise<number> { const w = W(); return w ? w.arrange(mode) : 1; },
  async windowTabs(op: string): Promise<number> { const w = W(); if (w) return w.windowTabs(op); lsSet("archi.ws.windowTabs", op); return 1; },
  async fullScreen(): Promise<boolean> {
    const w = W();
    if (w) return w.fullScreen();
    try { if (document.fullscreenElement) await document.exitFullscreen(); else await document.documentElement.requestFullscreen(); } catch {}
    return !!document.fullscreenElement;
  },
  async exportSettings(local: Record<string, string>): Promise<{ path: string; count: number } | null> {
    const w = W();
    if (w) return w.exportSettings(local);
    const data = { format: "oanarina-archi-settings", version: 1, app: {}, ui: local };
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([JSON.stringify(data, null, 1)], { type: "application/json" }));
    a.download = "Oanarina Archi Tool Settings.json";
    a.click();
    return { path: a.download, count: Object.keys(local).length };
  },
  async importSettings(): Promise<{ count?: number; ui?: Record<string, string>; error?: string } | null> {
    const w = W();
    if (w) return w.importSettings();
    return new Promise((resolve) => {
      const inp = document.createElement("input");
      inp.type = "file"; inp.accept = ".json";
      inp.onchange = async () => {
        const f = inp.files?.[0];
        if (!f) return resolve(null);
        try { const d = JSON.parse(await f.text()); if (d?.format !== "oanarina-archi-settings") return resolve({ error: `Cannot read ${f.name}.` }); resolve({ count: Object.keys(d.ui ?? {}).length, ui: d.ui ?? {} }); }
        catch { resolve({ error: `Cannot read ${f.name}.` }); }
      };
      inp.click();
    });
  },
  async crash(op: string, detail?: string): Promise<{ enabled: boolean; count: number; folder: string; environment: string; removed?: number; text?: string }> {
    const w = W();
    if (w) return w.crash(op, detail);
    if (op === "on" || op === "off") lsSet("archi.ws.crashReports", op === "on" ? "1" : "0");
    if (op === "text") return { enabled: false, count: 0, folder: "", environment: "", text: "" };
    return { enabled: lsGet("archi.ws.crashReports", "0") === "1", count: 0, folder: "%APPDATA%\\Oanarina Archi Tool\\Logs", environment: `Oanarina Archi Tool (web preview), ${navigator.userAgent}`, removed: 0 };
  },
  async assistantHasKey(): Promise<boolean> { const w = W(); return w ? w.assistantHasKey() : lsGet("archi.ws.assistantKey", "") !== ""; },
  async assistantSetKey(key: string): Promise<boolean> { const w = W(); if (w) return w.assistantSetKey(key); lsSet("archi.ws.assistantKey", key ? "set" : ""); return true; },
  async assistantRequest(req: { provider: string; endpoint: string; body: unknown }): Promise<{ text?: string; error?: string }> {
    const w = W();
    if (w) return w.assistantRequest(req);
    const fake = (window as any).archiAssistantFake;
    if (typeof fake === "function") return { text: JSON.stringify(await fake(req)) };
    return { error: "The assistant needs the Windows app (network access from the main process)." };
  },
};
