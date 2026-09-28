// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The Mac command search ranking (CommandSearch.rank in Dialogs.swift): exact name, alias, name prefix, alias prefix,
// name substring, ribbon / menu button title, summary, category, then letters in order ("prspl" finds PRESSPULL).
import ui from "../data/ui.generated.json";

export interface Searchable { name: string; aliases: string[]; category: string; summary: string }
export interface CatalogItem { title: string; command: string; names: string[]; args?: string; ui?: string }

/** Every ribbon, contextual tab and menu entry of the Mac catalogue (ui.generated.json) that runs something. */
export function catalogItems(): CatalogItem[] {
  const out: CatalogItem[] = [];
  const walk = (v: any) => {
    if (Array.isArray(v)) { for (const x of v) walk(x); return; }
    if (!v || typeof v !== "object") return;
    if (typeof v.command === "string" && v.command.trim() && !v.command.includes("{") && typeof v.title === "string") out.push({ title: v.title, command: v.command, names: v.names ?? [], args: v.args, ui: v.ui });
    for (const [k, x] of Object.entries(v)) if (k !== "help" && typeof x === "object") walk(x);
  };
  walk((ui as any).ribbon); walk((ui as any).contextualTabs); walk((ui as any).menus);
  return out;
}

let titles: Map<string, string[]> | null = null;
/** Ribbon / menu button titles per command name (so "Press/Pull" or "Tag All" find their commands). */
export function ribbonTitles(resolve: (n: string) => string | undefined): Map<string, string[]> {
  if (titles) return titles;
  titles = new Map();
  for (const it of catalogItems()) {
    if (it.command.startsWith("@")) continue;
    const name = [it.command.split(" ")[0], ...it.names].map((n) => resolve(n.split(" ")[0])).find(Boolean);
    if (name) { const l = titles.get(name) ?? []; l.push(it.title); titles.set(name, l); }
  }
  return titles;
}

export function isSubsequence(q: string, s: string): boolean {
  let i = 0;
  for (const ch of q) { i = s.indexOf(ch, i); if (i < 0) return false; i++; }
  return true;
}

export function rankCommands<T extends Searchable>(query: string, cmds: T[], titleMap: Map<string, string[]>, limit = 12): T[] {
  const q = query.trim().toUpperCase();
  if (!q) return [];
  const scored: [number, T][] = [];
  for (const c of cmds) {
    const aliases = (c.aliases ?? []).map((a) => a.toUpperCase());
    let s = Infinity;
    if (c.name === q) s = 0;
    else if (aliases.includes(q)) s = 1;
    else if (c.name.startsWith(q)) s = 10 + c.name.length;
    else if (aliases.some((a) => a.startsWith(q))) s = 60 + c.name.length;
    else if (c.name.includes(q)) s = 120 + c.name.length;
    else if ((titleMap.get(c.name) ?? []).some((t) => t.toUpperCase().includes(q))) s = 200 + c.name.length;
    else if (c.summary.toUpperCase().includes(q)) s = 300 + c.name.length;
    else if (c.category.toUpperCase().startsWith(q)) s = 500 + c.name.length;
    else if (q.length >= 3 && isSubsequence(q, c.name)) s = 700 + c.name.length;
    if (s !== Infinity) scored.push([s, c]);
  }
  scored.sort((a, b) => a[0] - b[0] || (a[1].name < b[1].name ? -1 : a[1].name > b[1].name ? 1 : 0));
  return scored.slice(0, limit).map((x) => x[1]);
}
