// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Spelling dialog (OutputDialogs.swift SpellingSheet, SPELLDIALOG): the engine lists every word of text, leaders,
// tables, dimension overrides and attributes (spell.words: the selection, or all); the Windows spell checker (Chromium's,
// which uses the Windows spell-checking service — the Mac uses NSSpellChecker) decides which are misspelled and
// suggests replacements. Change / Change All ("Spelling"), Ignore, Ignore All, Add to Dictionary (the drawing's
// SPELLDICT), Zoom To, Done.
import type { App } from "../app";
import { h, clear } from "../dom";
import { sheet, flatButton, spacer } from "../dialogs/ui";

export interface SpellChecker { isMisspelled(word: string): boolean; suggestions(word: string): string[] }

/** Web build / tests without Electron: a small list of common misspellings with their corrections. */
const COMMON: Record<string, string[]> = {
  wiht: ["with", "wit"], teh: ["the", "tech"], recieve: ["receive"], adress: ["address", "dress"], seperate: ["separate"], occured: ["occurred"],
  kitchn: ["kitchen"], bedrom: ["bedroom"], livng: ["living"], bathrom: ["bathroom"], stiar: ["stair", "star"], windw: ["window", "wind"], dor: ["door", "Dior"],
  flor: ["floor", "for"], balcny: ["balcony"], corridr: ["corridor"], garge: ["garage"], entrence: ["entrance"], ceilling: ["ceiling"],
};
function fallbackChecker(): SpellChecker {
  return { isMisspelled: (w) => w.toLowerCase() in COMMON, suggestions: (w) => {
    const s = COMMON[w.toLowerCase()] ?? [];
    return w[0] === w[0]?.toUpperCase() ? s.map((x) => x[0].toUpperCase() + x.slice(1)) : s;
  } };
}
export function spellChecker(): SpellChecker {
  const n = (window as any).archiSpell;
  if (n && typeof n.isMisspelled === "function") return { isMisspelled: (w) => !!n.isMisspelled(w), suggestions: (w) => n.suggestions(w) ?? [] };
  return fallbackChecker();
}

interface Word { entity: number; word: string; field: string }

export async function openSpelling(app: App) {
  const checker = spellChecker();
  const d = await app.tryCall("spell.words", {});
  const custom = new Set<string>((d?.custom ?? []).map((w: string) => w.toLowerCase()));
  // Words not accepted by the checker nor in the drawing dictionary; all-capital abbreviations are skipped (SpellCheck.misspelled).
  const words: Word[] = (d?.words ?? []).filter((w: Word) => !(w.word.length > 1 && w.word === w.word.toUpperCase()) && !custom.has(w.word.toLowerCase()) && checker.isMisspelled(w.word));
  let index = 0, changed = 0;
  const ignored = new Set<string>();
  const body = h("div", { class: "dt-spell" });
  const status = h("span", { class: "dt-dim" });
  const current = () => (index < words.length ? words[index] : null);
  let replacement = "";
  const skipIgnored = () => {
    while (current() && (ignored.has(current()!.word.toLowerCase()) || custom.has(current()!.word.toLowerCase()))) index++;
    const w = current();
    replacement = w ? checker.suggestions(w.word)[0] ?? "" : "";
  };
  const next = () => { index++; skipIgnored(); render(); };
  const render = () => {
    clear(body);
    status.textContent = `${Math.max(0, words.length - index)} left · ${changed} changed`;
    const w = current();
    if (!w) {
      body.append(h("div", { class: "dt-spell-done", text: words.length ? "Spelling check complete." : "No spelling errors found." }));
      doneBtn.classList.add("prominent");
      return;
    }
    doneBtn.classList.remove("prominent");
    const input = h("input", { class: "darkfield dt-spell-rep", value: replacement, spellcheck: false }) as HTMLInputElement;
    const change = flatButton("Change", () => void doChange(false), { prominent: true });
    const changeAll = flatButton("Change All", () => void doChange(true));
    const sync = () => { replacement = input.value; const off = !replacement || replacement === w.word; change.disabled = off; changeAll.disabled = off; };
    input.addEventListener("input", sync);
    const sugg = checker.suggestions(w.word).slice(0, 8);
    body.append(h("div", { class: "dt-small", text: "Not in dictionary:" }),
      h("div", { class: "dt-spell-word" }, h("span", { class: "w", text: w.word }), h("span", { class: "dt-small", text: `#${w.entity} · ${w.field}` }), spacer(),
        flatButton("Zoom To", async () => { await app.tryCall("select.set", { ids: [w.entity] }); await app.refresh(["selection"]); await app.runCommand("ZOOM O"); }, { compact: true })),
      h("div", { class: "dt-spell-row" }, h("span", { text: "Change to" }), input));
    if (sugg.length) body.append(h("div", { class: "dt-spell-sugg" }, ...sugg.map((s) => flatButton(s, () => { input.value = s; sync(); }, { compact: true }))));
    body.append(h("div", { class: "dt-spell-actions" }, change, changeAll, flatButton("Ignore", next), flatButton("Ignore All", () => { ignored.add(w.word.toLowerCase()); next(); }),
      flatButton("Add to Dictionary", () => void add(w.word))));
    sync();
  };
  const doChange = async (all: boolean) => {
    const w = current();
    if (!w || !replacement || replacement === w.word) return;
    const targets = all ? words.slice(index).filter((x) => x.word === w.word).map((x) => x.entity) : [w.entity];
    const r = await app.tryCall("spell.replace", { word: w.word, replacement, ids: [...new Set(targets)] });
    changed += Number(r?.changed ?? 0);
    if (all) ignored.add(w.word.toLowerCase());
    await app.refresh(["drawing", "history", "properties"]);
    next();
  };
  const add = async (word: string) => {
    const r = await app.tryCall("spell.add", { word });
    for (const c of r?.custom ?? []) custom.add(String(c).toLowerCase());
    await app.refresh(["history"]);
    next();
  };
  const doneBtn = flatButton("Done", () => handle.close());
  skipIgnored();
  render();
  const title = h("div", { class: "dt-spell-head" }, h("span", { text: "Check Spelling" }), spacer(), status);
  const handle = sheet({ title, width: 520, content: body, footerButtons: [doneBtn], onCancel: null, cls: "dt-spelling" });
  return handle;
}
