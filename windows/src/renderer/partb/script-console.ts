// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// JavaScript console (ScriptConsoleView.swift): code editor with highlighting, completion and indentation, Run (Ctrl+Enter),
// Run Selection (Ctrl+Shift+Enter), Examples, Snippets, the script Library (startup.js), recent scripts, open/save .js,
// the archi API reference, reset of the JavaScript context and the coloured output (double-click an error to go to its line).
import type { App } from "../app";
import { h, clear, button, iconButton, menuButton, spacer, promptText, load, store, Sheet, ico, type MenuItem } from "./ui";
import * as N from "./native";
import { prefs } from "../prefs";
import { EXAMPLES, API, SNIPPETS, API_MEMBERS, GLOBALS } from "./script-data";

type Kind = "input" | "output" | "value" | "error" | "warning";

export const ScriptLibrary = {
  async folder(): Promise<string> { const custom = String(prefs.get("scriptsFolder") ?? "") || load<string>("scriptsFolder", ""); return custom || (await N.paths()).scripts; },
  async ensure() {
    const f = await this.folder();
    await N.mkdir(f);
    const ex = N.join(f, "startup.example.js");
    if (!(await N.exists(ex)) && !(await N.list(f)).length) {
      await N.writeText(ex, "// startup.js runs in every new document window when Settings ▸ General ▸ Scripts is on.\n// Rename this file to startup.js to try it. The archi API is documented in the Script console.\n// archi.print(\"Hello from startup.js — layers:\", archi.layers().length);\n");
    }
  },
  async scripts(): Promise<N.FileEntry[]> { await this.ensure(); return (await N.list(await this.folder(), ["js", "scr", "txt"])).filter((f) => !f.dir); },
  async save(name: string, code: string): Promise<string> {
    await this.ensure();
    let n = name.trim() || "script";
    if (!n.toLowerCase().endsWith(".js")) n += ".js";
    const p = N.join(await this.folder(), n.replace(/[\\/]/g, "-"));
    await N.writeText(p, code);
    return p;
  },
  async reveal(app: App) { await this.ensure(); await N.reveal(app, await this.folder()); },
};

/** Runs a script file: .js in the window's JavaScript context, .scr/.txt as command lines (AppModel.runScriptFile). */
export async function runScriptFile(app: App, path: string) {
  const text = await N.readText(path);
  const name = N.basename(path);
  if (text === null) { app.print(`Cannot read script ${name}.`); return; }
  app.print(`Running script ${name}…`);
  if (/\.js$/i.test(path)) {
    const r = await N.scriptEval(app, text, name);
    for (const l of r.output) app.print(l);
    if (r.error) app.print(`Script error: ${r.error}`); else if (r.value !== null) app.print(`→ ${r.value}`);
  } else {
    await app.call("script.call", { fn: "run", args: [text] }).catch(() => null);
    app.print(`Script ${name} finished.`);
  }
  await app.refresh(["document", "selection"]);
  app.canvas?.zoomExtents();
}

/** startup.js from the script library in every new window (Settings ▸ General ▸ Scripts, on by default). */
export async function runStartup(app: App) {
  if (!prefs.get("runStartupScript") || !N.isElectron()) return;
  const p = N.join(await ScriptLibrary.folder(), "startup.js");
  if (await N.exists(p)) await runScriptFile(app, p);
}

const KW = /\b(const|let|var|function|return|if|else|for|while|do|of|in|new|break|continue|switch|case|default|try|catch|finally|throw|typeof|class|this|true|false|null|undefined)\b/g;

function escapeHTML(s: string) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }

/** Syntax colouring (the Mac regexes: numbers, keywords, archi/console/Math, strings, comments). */
export function highlight(src: string): string {
  const tokens: { s: number; e: number; cls: string }[] = [];
  const mark = (re: RegExp, cls: string) => { re.lastIndex = 0; let m: RegExpExecArray | null; while ((m = re.exec(src))) { tokens.push({ s: m.index, e: m.index + m[0].length, cls }); if (!m[0].length) re.lastIndex++; } };
  // Later marks win (the Mac paints comments last).
  mark(/\b\d+(\.\d+)?\b/g, "num");
  mark(new RegExp(KW.source, "g"), "kw");
  mark(/\b(archi|console|Math)\b/g, "api");
  mark(/"(\\.|[^"\\\n])*"|'(\\.|[^'\\\n])*'|`[^`]*`/g, "str");
  mark(/\/\/[^\n]*|\/\*[\s\S]*?\*\//g, "com");
  const cls: (string | null)[] = new Array(src.length).fill(null);
  for (const t of tokens) for (let i = t.s; i < t.e; i++) cls[i] = t.cls;
  let out = "", cur: string | null = null, buf = "";
  const flush = () => { if (!buf) return; out += cur ? `<span class="${cur}">${escapeHTML(buf)}</span>` : escapeHTML(buf); buf = ""; };
  for (let i = 0; i < src.length; i++) { if (cls[i] !== cur) { flush(); cur = cls[i]; } buf += src[i]; }
  flush();
  return out + "\n";
}

/** Completion candidates (ScriptCompletion.candidates). */
export function completions(app: App, prefix: string, before: string): string[] {
  const p = prefix.toLowerCase();
  if (before.endsWith("archi.")) return API_MEMBERS.filter((n) => !p || n.toLowerCase().startsWith(p));
  const r = before.lastIndexOf('archi.run("');
  if (r >= 0 && !before.slice(r + 11).includes('"')) {
    const all = new Set<string>();
    for (const c of app.hello.commands ?? []) { all.add(c.name); for (const a of c.aliases ?? []) all.add(a); }
    return [...all].filter((n) => !p || n.toLowerCase().startsWith(p)).sort().slice(0, 200);
  }
  if (!p) return [];
  return GLOBALS.filter((g) => g.toLowerCase().startsWith(p) && g.toLowerCase() !== p);
}

export class ScriptConsole {
  el: HTMLElement;
  private code: HTMLTextAreaElement;
  private pre: HTMLElement;
  private out: HTMLElement;
  private runBtn: HTMLButtonElement;
  private selBtn: HTMLButtonElement;
  private running = false;
  private history: string[] = load<string[]>("script.history", []);
  private popup: HTMLElement | null = null;

  constructor(private app: App) {
    this.code = h("textarea", { spellcheck: false, "aria-label": "Script" }) as HTMLTextAreaElement;
    this.pre = h("pre", { "aria-hidden": "true" });
    const editor = h("div", { class: "pb-code" }, this.pre, this.code);
    this.out = h("div", { class: "pb-out", role: "log" });
    this.code.value = localStorage.getItem("archi.script.code") ?? EXAMPLES[3].code;
    this.paint();
    this.runBtn = button("Run", { icon: "play.fill", compact: true, help: "Run script (Ctrl+Enter)", onClick: () => this.run() });
    this.selBtn = button("Run Selection", { icon: "text.cursor", compact: true, help: "Run only the selected code (Ctrl+Shift+Enter)", onClick: () => this.runSelection(), disabled: true });
    for (const b of [this.runBtn, this.selBtn]) b.style.border = "0";
    const bar = h("div", { class: "pb-console-bar" },
      this.runBtn, this.selBtn,
      menuButton("Examples", null, () => EXAMPLES.map((ex) => ({ title: ex.name, action: () => this.setCode(ex.code) }))),
      menuButton("Snippets", null, () => this.snippetMenu(), "Insert a code snippet at the cursor (Ctrl+Space or Esc completes the archi API)"),
      menuButton("Library", null, () => this.libraryMenu()),
      menuButton(ico("clock.arrow.circlepath", 12), null, () => this.history.length ? this.history.map((x) => ({ title: (x.split("\n")[0] ?? "").slice(0, 60) + (x.includes("\n") ? " …" : ""), action: () => this.setCode(x) })) : [{ title: "No scripts run yet", disabled: true }], "Recently run scripts"),
      iconButton("folder", "Open .js file", () => this.open()),
      iconButton("square.and.arrow.down", "Save as .js file", () => this.save()),
      iconButton("book", "archi API reference", () => this.apiReference()),
      spacer(),
      iconButton("arrow.counterclockwise", "Reset the JavaScript context", async () => { await N.scriptReset(this.app); this.line("output", "JavaScript context reset."); }),
      iconButton("trash", "Clear output", () => clear(this.out)));
    const divider = h("div", { class: "pb-divider" });
    const split = h("div", { class: "pb-split" }, editor, divider, this.out);
    this.el = h("div", { class: "pb-console", "data-console": "1" }, bar, h("div", { class: "pb-hsep" }), split);
    this.el.style.height = load<number>("console.height", 210) + "px";
    let edH = load<number>("console.editor", 130);
    editor.style.flex = "none"; editor.style.height = edH + "px";
    divider.addEventListener("mousedown", (e) => {
      const y0 = e.clientY, e0 = editor.getBoundingClientRect().height;
      const mv = (ev: MouseEvent) => { edH = Math.max(60, Math.min(this.el.getBoundingClientRect().height - 90, e0 + ev.clientY - y0)); editor.style.height = edH + "px"; };
      const up = () => { removeEventListener("mousemove", mv); removeEventListener("mouseup", up); store("console.editor", edH); };
      addEventListener("mousemove", mv); addEventListener("mouseup", up); e.preventDefault();
    });
    this.wireEditor();
    N.initScripts(app);
    N.onScriptLine((t) => this.line(t.startsWith("✖") ? "error" : t.startsWith("⚠") ? "warning" : "output", t));
    this.out.addEventListener("dblclick", (e) => { const t = (e.target as HTMLElement).closest(".error")?.textContent ?? ""; this.goToLine(t); });
    this.out.addEventListener("contextmenu", (e) => {
      e.preventDefault();
      import("./ui").then(({ showMenu }) => showMenu([{ title: "Copy Output", action: () => N.copy([...this.out.children].map((c) => c.textContent).join("\n")) }], { x: e.clientX, y: e.clientY }));
    });
  }

  private paint() { this.pre.innerHTML = highlight(this.code.value); }
  setCode(s: string) { this.code.value = s; this.paint(); localStorage.setItem("archi.script.code", s); }
  focus() { this.code.focus(); }

  line(kind: Kind, text: string) {
    const d = h("div", { class: kind, text });
    if (kind === "error" && text.includes("(line ")) d.title = "Double-click to go to the line";
    this.out.append(d);
    while (this.out.childElementCount > 3000) for (let i = 0; i < 1000; i++) this.out.firstElementChild?.remove();
    this.out.scrollTop = this.out.scrollHeight;
  }

  private goToLine(text: string) {
    const m = /\(line (\d+)/.exec(text);
    if (!m) return;
    const n = Number(m[1]);
    const lines = this.code.value.split("\n");
    let start = 0;
    for (let i = 0; i < Math.min(n - 1, lines.length); i++) start += lines[i].length + 1;
    const end = start + (lines[n - 1]?.length ?? 0);
    this.code.focus();
    this.code.setSelectionRange(start, end);
  }

  private selected() { return this.code.value.slice(this.code.selectionStart, this.code.selectionEnd); }

  async run(src = this.code.value) {
    if (this.running || !src.trim()) return;
    this.history = [src, ...this.history.filter((x) => x !== src)].slice(0, 15);
    store("script.history", this.history);
    this.running = true;
    this.runBtn.disabled = true;
    (this.runBtn.lastChild as HTMLElement).textContent = "Running…";
    this.line("input", "▶ " + (src.split("\n")[0] ?? "") + (src.includes("\n") ? " …" : ""));
    try {
      const r = await N.scriptEval(this.app, src, "console.js");
      if (r.value !== null && r.value !== "null") this.line("value", "⇐ " + r.value);
    } finally {
      this.running = false;
      this.runBtn.disabled = false;
      (this.runBtn.lastChild as HTMLElement).textContent = "Run";
      await this.app.refresh(["document", "selection"]);
    }
  }
  runSelection() { this.run(this.selected()); }

  private insert(text: string) {
    const s = this.code.selectionStart, e = this.code.selectionEnd;
    this.code.setRangeText(text, s, e, "end");
    this.paint();
    localStorage.setItem("archi.script.code", this.code.value);
    this.code.focus();
  }

  private snippetMenu(): MenuItem[] {
    const user = load<Record<string, string>>("script.snippets", {});
    const items: MenuItem[] = [{ header: "Built-in" }, ...SNIPPETS.map(([n, body]) => ({ title: n, action: () => this.insert(body) }))];
    const names = Object.keys(user).sort();
    if (names.length) {
      items.push({ header: "My Snippets" }, ...names.map((n) => ({ title: n, action: () => this.insert(user[n]) })));
      items.push({ title: "Delete Snippet", submenu: names.map((n) => ({ title: n, action: () => { const u = load<Record<string, string>>("script.snippets", {}); delete u[n]; store("script.snippets", u); this.line("output", `Snippet "${n}" deleted.`); } })) });
    }
    items.push({ separator: true }, { title: "Save Selection as Snippet…", disabled: !this.selected().trim(), action: () => this.saveSnippet() });
    return items;
  }
  private async saveSnippet() {
    const body = this.selected();
    const user = load<Record<string, string>>("script.snippets", {});
    const n = (await promptText("Save Snippet", "", `My snippet ${Object.keys(user).length + 1}`))?.trim();
    if (!n) return;
    user[n] = body; store("script.snippets", user);
    this.line("output", `Snippet "${n}" saved.`);
  }

  private libraryCache: N.FileEntry[] = [];
  private libraryMenu(): MenuItem[] {
    ScriptLibrary.scripts().then((s) => { this.libraryCache = s; });
    const items: MenuItem[] = this.libraryCache.length ? this.libraryCache.map((f) => ({
      title: f.name, submenu: [
        { title: "Open in Editor", action: async () => { const t = await N.readText(f.path); if (t !== null) this.setCode(t); } },
        { title: "Run", action: () => runScriptFile(this.app, f.path) },
      ],
    })) : [{ title: "The library is empty", disabled: true }];
    items.push({ separator: true },
      { title: "Save Editor to Library…", action: () => this.saveToLibrary() },
      { title: "Save as startup.js", action: () => this.saveToLibrary("startup.js") },
      { title: "Open Library Folder", action: () => ScriptLibrary.reveal(this.app) });
    return items;
  }
  async refreshLibrary() { this.libraryCache = await ScriptLibrary.scripts(); }
  private async saveToLibrary(name?: string) {
    const n = name ?? (await promptText("Save to Script Library", "", "my-script.js"));
    if (!n) return;
    try { const p = await ScriptLibrary.save(n, this.code.value); this.line("output", `Saved to the library: ${N.basename(p)}`); this.refreshLibrary(); }
    catch (e: any) { this.line("error", "✖ " + (e?.message ?? e)); }
  }

  private async open() {
    const p = await N.openFile(this.app, "Open Script", [{ name: "JavaScript", extensions: ["js"] }, { name: "Text", extensions: ["txt"] }]);
    if (!p) return;
    const t = await N.readText(p);
    if (t !== null) this.setCode(t);
  }
  private async save() {
    const p = await N.saveFile(this.app, "Save Script", "script.js", [{ name: "JavaScript", extensions: ["js"] }]);
    if (!p) return;
    try { await N.writeText(p, this.code.value); } catch (e: any) { this.line("error", "✖ " + (e?.message ?? e)); }
  }

  /** archi API reference (the Mac popover) with Insert buttons. */
  apiReference() {
    const s = new Sheet(460);
    const list = h("div", { class: "pb-scroll pb-col", style: { padding: "12px", gap: "10px", maxHeight: "480px" } });
    for (const [sig, doc, ex] of API) {
      list.append(h("div", { class: "pb-col", style: { gap: "3px" } },
        h("div", { class: "pb-row" }, h("span", { class: "pb-mono pb-accent", style: { fontWeight: "600", fontSize: "11.5px" }, text: sig }), spacer(),
          button("Insert", { compact: true, onClick: () => { const c = this.code.value; this.setCode(c + (c.endsWith("\n") || !c ? "" : "\n") + ex); } })),
        h("div", { class: "pb-small", text: doc }),
        h("div", { class: "pb-mono pb-dim", style: { fontSize: "10.5px", whiteSpace: "pre-wrap", userSelect: "text" }, text: ex })));
    }
    list.append(h("div", { class: "pb-small pb-dim", text: "Full reference: docs/SCRIPTING.md (Help ▸ User Guide)." }));
    s.body.append(h("div", { class: "pb-sheet-head" }, h("span", { text: "archi API" }), spacer(), button("Done", { prominent: true, onClick: () => s.close() })), h("div", { class: "pb-hsep" }), list);
  }

  private wireEditor() {
    const c = this.code;
    c.addEventListener("input", () => {
      this.paint();
      localStorage.setItem("archi.script.code", c.value);
      const before = c.value.slice(0, c.selectionStart);
      if (before.endsWith("archi.") || before.endsWith('archi.run("')) this.complete(); else if (this.popup) this.complete(true);
    });
    c.addEventListener("scroll", () => { this.pre.style.transform = `translate(${-c.scrollLeft}px, ${-c.scrollTop}px)`; });
    const syncSel = () => { this.selBtn.disabled = this.running || !this.selected().trim(); };
    c.addEventListener("select", syncSel); c.addEventListener("keyup", syncSel); c.addEventListener("mouseup", syncSel);
    c.addEventListener("keydown", (e) => {
      e.stopPropagation();
      if (this.popup && this.popupKey(e)) return;
      if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) { e.preventDefault(); if (e.shiftKey) this.runSelection(); else this.run(); return; }
      if ((e.key === " " && e.ctrlKey) || (e.key === "Escape" && !e.shiftKey && !e.altKey)) { e.preventDefault(); this.complete(); return; }
      if (e.key === "Tab" && !e.shiftKey) { e.preventDefault(); this.insert("  "); return; }
      if (e.key === "Enter") {
        const before = c.value.slice(0, c.selectionStart);
        const lineStart = before.lastIndexOf("\n") + 1;
        const line = before.slice(lineStart);
        let indent = /^[ \t]*/.exec(line)?.[0] ?? "";
        if (line.trim().endsWith("{")) indent += "  ";
        e.preventDefault();
        this.insert("\n" + indent);
      }
    });
    c.addEventListener("blur", () => setTimeout(() => this.closePopup(), 150));
  }

  private words(): { prefix: string; before: string } {
    const before = this.code.value.slice(0, this.code.selectionStart);
    const m = /[\w.]*$/.exec(before)?.[0] ?? "";
    const prefix = m.includes(".") ? m.slice(m.lastIndexOf(".") + 1) : m;
    return { prefix, before: before.slice(0, before.length - prefix.length) };
  }
  private selIdx = 0;
  private items: string[] = [];
  private complete(update = false) {
    const { prefix, before } = this.words();
    const list = completions(this.app, prefix, before);
    if (!list.length) { this.closePopup(); return; }
    this.items = list; if (!update) this.selIdx = 0; else this.selIdx = Math.min(this.selIdx, list.length - 1);
    if (!this.popup) { this.popup = h("div", { class: "pb-completions" }); document.body.append(this.popup); }
    clear(this.popup);
    list.forEach((n, i) => {
      const d = h("div", { class: i === this.selIdx ? "sel" : "", text: n });
      d.addEventListener("mousedown", (e) => { e.preventDefault(); this.accept(n); });
      this.popup!.append(d);
    });
    const r = this.code.getBoundingClientRect();
    const lines = this.code.value.slice(0, this.code.selectionStart).split("\n");
    const x = r.left + 6 + (lines[lines.length - 1].length * 7.2) - this.code.scrollLeft, y = r.top + 8 + lines.length * 17 - this.code.scrollTop;
    Object.assign(this.popup.style, { left: Math.min(innerWidth - 220, x) + "px", top: Math.min(innerHeight - 230, y) + "px" });
  }
  private accept(n: string) {
    const { prefix } = this.words();
    const s = this.code.selectionStart;
    this.code.setRangeText(n, s - prefix.length, s, "end");
    this.paint();
    this.closePopup();
    this.code.focus();
  }
  private popupKey(e: KeyboardEvent): boolean {
    if (e.key === "ArrowDown") { this.selIdx = (this.selIdx + 1) % this.items.length; this.complete(true); e.preventDefault(); return true; }
    if (e.key === "ArrowUp") { this.selIdx = (this.selIdx - 1 + this.items.length) % this.items.length; this.complete(true); e.preventDefault(); return true; }
    if (e.key === "Enter" || e.key === "Tab") { this.accept(this.items[this.selIdx]); e.preventDefault(); return true; }
    if (e.key === "Escape") { this.closePopup(); e.preventDefault(); return true; }
    return false;
  }
  private closePopup() { this.popup?.remove(); this.popup = null; }
}
