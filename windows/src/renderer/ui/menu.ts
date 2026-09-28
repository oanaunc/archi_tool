// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Dark popup menus (ribbon menus, dropdowns, title-bar menus, context menus) and hover tooltips.
import { h } from "../dom";
import { icon } from "../icons";

export interface MenuItem {
  title?: string; symbol?: string; swatch?: string; checked?: boolean; disabled?: boolean; shortcut?: string;
  separator?: boolean; header?: string; action?: () => void; submenu?: MenuItem[];
}
let open: HTMLElement[] = [];
let onCloseCb: (() => void) | null = null;

/** Document the next menu at a point opens in: the drawing window, or a floating panel window (workspace/float.ts)
 *  after a mouse press there — so a context menu opens where it was asked for. */
let menuDoc: Document = document;
export function closeMenus() { open.forEach((m) => m.remove()); open = []; const cb = onCloseCb; onCloseCb = null; cb?.(); }

export function showMenu(items: MenuItem[], at: { x: number; y: number } | HTMLElement, opts: { level?: number; onClose?: () => void; minWidth?: number } = {}): HTMLElement {
  const level = opts.level ?? 0;
  if (level === 0) { closeMenus(); onCloseCb = opts.onClose ?? null; }
  else { open.slice(level).forEach((m) => m.remove()); open = open.slice(0, level); }
  const m = h("div", { class: "menu", role: "menu" });
  if (opts.minWidth) m.style.minWidth = opts.minWidth + "px";
  for (const it of items) {
    if (it.separator) { m.append(h("div", { class: "sep" })); continue; }
    if (it.header !== undefined) { m.append(h("div", { class: "hdr", text: it.header.toUpperCase() })); continue; }
    const ico = h("span", { class: "ico" });
    if (it.checked) ico.append(icon("checkmark", 13, 2));
    else if (it.swatch) ico.append(h("span", { class: "swatch", style: { background: it.swatch } }));
    else if (it.symbol) ico.append(icon(it.symbol, 14));
    const row = h("div", { class: "mi" + (it.disabled ? " disabled" : "") + (it.submenu ? " sub" : ""), role: "menuitem" }, ico, h("span", { text: it.title ?? "" }), it.shortcut ? h("span", { class: "sc", text: it.shortcut }) : null);
    row.addEventListener("mouseenter", () => {
      if (it.submenu && !it.disabled) { const r = row.getBoundingClientRect(); showMenu(it.submenu, { x: r.right - 2, y: r.top - 5 }, { level: level + 1 }); }
      else if (open.length > level + 1) { open.slice(level + 1).forEach((x) => x.remove()); open = open.slice(0, level + 1); }
    });
    row.addEventListener("mousedown", (e) => e.preventDefault());
    row.addEventListener("click", (e) => { e.stopPropagation(); if (it.disabled || it.submenu) return; closeMenus(); it.action?.(); });
    m.append(row);
  }
  const doc = "getBoundingClientRect" in at ? (at as HTMLElement).ownerDocument : (level ? open[0]?.ownerDocument ?? menuDoc : menuDoc);
  const view = doc.defaultView ?? window;
  const innerWidth = view.innerWidth, innerHeight = view.innerHeight;
  doc.body.append(m);
  open.push(m);
  let x: number, y: number;
  if ("getBoundingClientRect" in at) { const r = (at as HTMLElement).getBoundingClientRect(); x = r.left; y = r.bottom + 2; if (!opts.minWidth) m.style.minWidth = Math.max(180, r.width) + "px"; }
  else { x = at.x; y = at.y; }
  const mr = m.getBoundingClientRect();
  if (x + mr.width > innerWidth - 4) x = Math.max(4, level ? x - mr.width - ("getBoundingClientRect" in at ? 0 : 180) : innerWidth - mr.width - 4);
  if (y + mr.height > innerHeight - 4) y = Math.max(4, innerHeight - mr.height - 4);
  m.style.left = x + "px"; m.style.top = y + "px";
  return m;
}

/** Menu dismissal (click outside, Escape, losing the focus) in a window: the drawing window, and each floating panel
 *  window, whose presses also make it the window context menus open in. */
export function attachMenuWindow(w: Window) {
  const own = w.document;
  w.addEventListener("mousedown", (e) => { menuDoc = own; if (open.length && !open.some((m) => m.contains(e.target as Node))) closeMenus(); }, true);
  w.addEventListener("contextmenu", () => { menuDoc = own; }, true);
  w.addEventListener("keydown", (e) => { if (e.key === "Escape" && open.length) { closeMenus(); e.stopPropagation(); e.preventDefault(); } }, true);
  w.addEventListener("blur", () => { if (open.some((m) => m.ownerDocument === own)) closeMenus(); });
  w.addEventListener("pagehide", () => { if (menuDoc === own) menuDoc = document; });
}
attachMenuWindow(window);

// ---- tooltips (the Mac .help(...) strings) ----
let tip: HTMLElement | null = null, tipTimer = 0;
export function help(el: HTMLElement, text: string) {
  if (!text) return;
  el.setAttribute("aria-label", text);
  el.addEventListener("mouseenter", () => {
    clearTimeout(tipTimer);
    tipTimer = window.setTimeout(() => {
      tip?.remove();
      tip = h("div", { class: "tooltip", text });
      el.ownerDocument.body.append(tip);  // the window the control is in (floating panels are separate windows)
      const view = el.ownerDocument.defaultView ?? window, innerWidth = view.innerWidth, innerHeight = view.innerHeight;
      const r = el.getBoundingClientRect(), tr = tip.getBoundingClientRect();
      tip.style.left = Math.min(innerWidth - tr.width - 4, Math.max(4, r.left + r.width / 2 - tr.width / 2)) + "px";
      tip.style.top = (r.bottom + 6 + tr.height > innerHeight ? r.top - tr.height - 6 : r.bottom + 6) + "px";
    }, 700);
  });
  const hide = () => { clearTimeout(tipTimer); tip?.remove(); tip = null; };
  el.addEventListener("mouseleave", hide);
  el.addEventListener("mousedown", hide);
}
