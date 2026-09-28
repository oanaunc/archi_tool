// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Interface language of the ribbon and menus (Localization.swift, LocalizationMenus.swift; SYS-026): English, Romanian,
// German, French, Spanish and Italian. Command names typed on the command line stay English, so scripts work in every
// language. "auto" follows the Windows display language. Table: data/l10n.generated.json (tools/gen-l10n.mjs).
import data from "../data/l10n.generated.json";

const D = data as unknown as { languages: [string, string][]; order: string[]; table: Record<string, string[]>; menuTable: Record<string, string[]> };
export const LANGUAGES = D.languages.map(([code, name]) => ({ code, name }));
const KEY = "archi.uiLanguage";

export function languageSetting(): string { try { return localStorage.getItem(KEY) ?? "auto"; } catch { return "auto"; } }
export function setLanguageSetting(code: string) { try { localStorage.setItem(KEY, code); } catch {} cache = null; }
/** First Windows display language the table has (navigator.languages), else English. */
export function systemLanguage(preferred: readonly string[] = navigator.languages ?? [navigator.language]): string {
  for (const p of preferred) { const c = String(p).slice(0, 2).toLowerCase(); if (LANGUAGES.some((l) => l.code === c)) return c; }
  return "en";
}
export function resolvedLanguage(s = languageSetting()): string { return s !== "auto" ? (LANGUAGES.some((l) => l.code === s) ? s : "en") : systemLanguage(); }
let cache: string | null = null;
/** Translation of an English ribbon or menu string (the English text when there is none). */
export function t(s: string, lang?: string): string {
  const l = lang ?? (cache ??= resolvedLanguage());
  if (l === "en" || !s) return s;
  const row = D.table[s] ?? D.menuTable[s];
  const i = D.order.indexOf(l);
  return row && i >= 0 && i < row.length ? row[i] : s;
}
/** Menu tree with translated titles (menus built from the Mac catalogue: titles, submenus and items). */
export function translateMenu<T extends { title?: string; submenu?: T[]; items?: T[] }>(items: T[]): T[] {
  if (resolvedLanguage() === "en") return items;
  return items.map((it) => ({ ...it, ...(it.title ? { title: t(it.title) } : {}), ...(it.submenu ? { submenu: translateMenu(it.submenu) } : {}), ...(it.items ? { items: translateMenu(it.items) } : {}) }));
}
