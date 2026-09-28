// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Lineweight display scale (LWDISPLAYSCALE, LineweightDisplay in AppNavigation.swift): screen scale of displayed
// lineweights, 0.1–5 (default 1), an application setting; plotted widths never change.
const KEY = "archi.lwDisplayScale";
export function lwDisplayScale(): number {
  try { const v = Number(localStorage.getItem(KEY)); return v > 0 ? Math.min(Math.max(v, 0.1), 5) : 1; } catch { return 1; }
}
export function setLwDisplayScale(v: number) {
  try { localStorage.setItem(KEY, String(Math.min(Math.max(v, 0.1), 5))); } catch { /* private mode */ }
}
