// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// SPELL / SPELLCHECK on the command line, in scripts and from agents, with the Windows spell checker: the Mac installs
// NSSpellChecker in the engine (SpellCheck.checker); on Windows the checker lives in the shell (Chromium's, which uses
// the Windows spell-checking service and the user's languages). Before a SPELL command reaches the engine the shell
// lists the drawing's words (spell.words), asks the checker which are misspelled with their suggestions and gives the
// verdicts to the engine (spell.verdicts), so the engine's SPELL runs with the Mac's prompts and messages:
//   Not in dictionary: "Kitchn" (#12 text) — suggestions: Kitchen, …
//   Change to or [Ignore/ignore All/Add] <Kitchen>:
import type { App } from "../app";
import { spellChecker } from "../doctools/spelling";

const SPELL = /^\s*(SPELL|SPELLCHECK)(\s|$)/i;

/** Gives the engine the checker's verdicts for every word of the drawing. */
export async function primeSpelling(call: (m: string, p: unknown) => Promise<any>): Promise<number> {
  const checker = spellChecker();
  let words: { word: string }[] = [];
  try { words = (await call("spell.words", { all: true }))?.words ?? []; } catch { return 0; }
  const misspelled: Record<string, string[]> = {};
  for (const w of words) {
    if (w.word in misspelled) continue;
    try { if (checker.isMisspelled(w.word)) misspelled[w.word] = checker.suggestions(w.word).slice(0, 8); } catch {}
  }
  try { await call("spell.verdicts", { misspelled }); } catch {}
  return Object.keys(misspelled).length;
}

function startsSpell(app: App, method: string, p: any): boolean {
  if (method === "command.run") {
    if (app.prompt.active && !p?.cancel) return false;
    const tok = String(p?.line ?? "").trim().split(/\s+/)[0] ?? "";
    return !!tok && app.lookup(tok)?.name === "SPELL";
  }
  if (method === "script.call" && p?.fn === "run") return [].concat(p.args?.[0] ?? []).some((l: any) => SPELL.test(String(l)));
  if (method === "agent.call" && p?.method === "run_command") return SPELL.test(String(p.params?.command ?? p.params?.line ?? ""));
  return false;
}

/** Wraps the engine connection so every way of starting SPELL primes the checker first. */
export function installSpellCommand(app: App) {
  const engine = app.engine as any;
  const call = engine.call.bind(engine);
  engine.call = async (method: string, params?: unknown) => {
    if (startsSpell(app, method, params)) await primeSpelling(call);
    return call(method, params);
  };
}
