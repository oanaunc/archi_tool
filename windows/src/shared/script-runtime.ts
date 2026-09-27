// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The `archi` JavaScript API of the script console, plugins and agents (the Mac ScriptEngine, ArchiApp/ScriptEngine.swift),
// running in a worker of the Windows shell (V8): every archi.* call is a synchronous engine request (`script.call`) over
// a SharedArrayBuffer channel, so scripts written for the Mac run unchanged. Output, errors (with the source line and a
// caret), console extras, event hooks, script panels and registered commands behave as on the Mac.

/** Synchronous link to the engine and the window, provided by the worker entry. */
export interface ScriptChannel {
  /** An engine request (JSON-RPC method and params); returns the result or throws {code, message}. */
  call(method: string, params: unknown): any;
  /** One output line (the console colours lines starting with ✖ as errors and ⚠ as warnings). */
  emit(line: string): void;
  /** Script-defined panel (archi.panel). */
  panel(spec: unknown): void;
  /** Events with at least one handler (the host watches the document for them). */
  hooks(events: string[]): void;
}

export interface ScriptResult { output: string[]; value: string | null; error: string | null }

export const HOOK_EVENTS = ["selectionChanged", "documentChanged", "elementAdded", "elementRemoved", "saved", "commandEnded"];

/** Source line `line` (1-based) with its neighbours and a caret under `column` (ScriptDiagnostics.excerpt). */
export function excerpt(source: string, line: number, column: number | null, context = 1): string[] {
  const lines = source.split("\n");
  if (line < 1 || line > lines.length) return [];
  const out: string[] = [];
  const w = String(Math.min(lines.length, line + context)).length;
  for (let i = Math.max(1, line - context); i <= Math.min(lines.length, line + context); i++) {
    out.push(`${i === line ? ">" : " "} ${String(i).padStart(w)} | ${lines[i - 1]}`);
    if (i === line && column !== null && column >= 1) out.push("  " + " ".repeat(w) + " | " + " ".repeat(Math.min(column - 1, 400)) + "^");
  }
  return out;
}

export class ScriptRuntime {
  private handlers = new Map<string, Function[]>();
  private output: string[] = [];
  private source = "";
  scriptName = "console.js";
  readonly archi: Record<string, any> = {};
  private g: any = globalThis as any;

  constructor(private ch: ScriptChannel) { this.install(); }

  private emit(line: string) { this.output.push(line); this.ch.emit(line); }

  describe(v: any): string {
    if (v === undefined) return "undefined";
    if (v !== null && typeof v === "object" && !(v instanceof Date)) {
      try { const s = JSON.stringify(v, null, 2); if (s !== undefined) return s; } catch { /* cyclic */ }
    }
    if (typeof v === "function") return v.toString();
    return String(v);
  }

  /** archi.* → script.call {fn, args}; engine errors become JavaScript exceptions with the engine's message. */
  private api(fn: string, ...args: any[]): any {
    try { return this.ch.call("script.call", { fn, args: args.map((a) => (a === undefined ? null : a)) }); }
    catch (e: any) { throw new Error(e?.message ?? String(e)); }
  }

  private install() {
    const a = this.archi, self = this;
    const print = (...args: any[]) => self.emit(args.map((x) => self.describe(x)).join(" "));
    a.print = print;
    a.run = (text?: string) => self.api("run", text === undefined ? "" : String(text));
    a.on = (name: string, fn: Function) => {
      const n = String(name);
      if (!HOOK_EVENTS.includes(n)) throw new Error(`unknown event '${n}' (${HOOK_EVENTS.join(", ")})`);
      if (typeof fn !== "function") throw new Error("archi.on needs a function");
      const list = self.handlers.get(n) ?? [];
      list.push(fn); self.handlers.set(n, list);
      self.ch.hooks([...self.handlers.keys()]);
      return list.length;
    };
    a.off = (name?: string) => {
      if (name === undefined) self.handlers.clear(); else self.handlers.delete(String(name));
      self.ch.hooks([...self.handlers.keys()]);
      return true;
    };
    a.panel = (spec: any) => {
      if (!spec || typeof spec !== "object") throw new Error("archi.panel needs {title, items}");
      const items = Array.isArray(spec.items) ? spec.items : [];
      for (const it of items) if (!it || typeof it !== "object" || !["number", "field", "toggle", "text", "button"].includes(String(it.type))) throw new Error(`panel item type must be number, field, toggle, text or button`);
      const clean = JSON.parse(JSON.stringify({ title: String(spec.title ?? "Script Panel"), items }));
      self.ch.panel(clean);
      return clean.title;
    };
    for (const fn of ["doc", "summary", "selection", "layers", "levels", "undo", "redo", "commands"]) a[fn] = () => self.api(fn);
    a.entities = (f?: any) => self.api("entities", f ?? null);
    a.elements = (f?: any) => self.api("elements", f ?? null);
    a.get = (id: number) => self.api("get", Number(id) | 0);
    a.add = (o: any) => self.api("add", o);
    a.addElement = (o: any) => self.api("addElement", o);
    a.update = (id: number, p: any) => self.api("update", Number(id) | 0, p ?? {});
    a.remove = (ids: any) => self.api("remove", ids);
    a.select = (ids: any) => self.api("select", ids);
    a.setVar = (n: any, v: any) => self.api("setVar", String(n), String(v));
    a.getVar = (n: any) => self.api("getVar", String(n));
    a.wall = (x1: number, y1: number, x2: number, y2: number, o?: any) => self.api("wall", Number(x1), Number(y1), Number(x2), Number(y2), o ?? null);
    for (const k of ["door", "window", "opening"]) a[k] = (w: number, off: number, o?: any) => self.api(k, Number(w) | 0, Number(off), o ?? null);
    a.slab = (p: any, o?: any) => self.api("slab", p, o ?? null);
    a.room = (p: any, n?: any, o?: any) => self.api("room", p, n === undefined ? "Room" : String(n), o ?? null);
    a.column = (x: number, y: number, o?: any) => self.api("column", Number(x), Number(y), o ?? null);
    a.evaluateGraph = (g: any) => self.api("evaluateGraph", g);
    a.bakeGraph = (g: any) => self.api("bakeGraph", g);
    a.registerCommand = (name: any, f: any, o?: any) => {
      if (typeof name !== "string" || !name) throw new Error("registerCommand(name, function[, options]) needs a command name");
      const fname = typeof f === "string" ? f : typeof f === "function" ? f.name : "";
      if (!fname) throw new Error(`registerCommand: pass a named global function (or its name) for ${name.toUpperCase()}`);
      const src = self.source.split(PLUGIN_CALL_MARKER)[0];
      return self.api("registerCommand", name.toUpperCase(), fname, o && typeof o === "object" ? o : null, src, self.scriptName);
    };
    this.g.archi = a;
    const con: any = { log: print, info: print, debug: print };
    con.warn = (...args: any[]) => self.emit("⚠ " + args.map((x) => self.describe(x)).join(" "));
    con.error = (...args: any[]) => self.emit("✖ " + args.map((x) => self.describe(x)).join(" "));
    const timers: Record<string, number> = {}, counts: Record<string, number> = {};
    con.assert = (c: any, ...rest: any[]) => { if (!c) con.error("Assertion failed:", ...rest); };
    con.time = (l?: string) => { timers[l || "default"] = Date.now(); };
    con.timeEnd = (l?: string) => { const k = l || "default"; if (timers[k] !== undefined) { con.log(k + ": " + (Date.now() - timers[k]) + " ms"); delete timers[k]; } else con.warn("No timer " + k); };
    con.count = (l?: string) => { const k = l || "default"; counts[k] = (counts[k] || 0) + 1; con.log(k + ": " + counts[k]); };
    con.trace = (...args: any[]) => { const s = new Error().stack || ""; con.log("Trace:", ...args); for (const f of s.split("\n").slice(2)) if (f.trim()) con.log("   at " + f.trim().replace(/^at /, "")); };
    this.g.console = con;
    this.g.print = print;
  }

  /** Error position in the evaluated source from a V8 stack ("…(console.js:3:7)"). */
  private position(e: any): { line: number; column: number } | null {
    const stack = String(e?.stack ?? "");
    const re = new RegExp(escapeRe(this.scriptName) + ":(\\d+):(\\d+)");
    const m = stack.match(re);
    if (m) return { line: Number(m[1]), column: Number(m[2]) };
    return null;
  }

  private report(e: any) {
    const name = e?.name && e.name !== "Error" ? e.name + ": " : e instanceof Error ? "Error: " : "";
    let msg = (e instanceof Error ? name + e.message : String(e));
    const pos = e instanceof Error ? this.position(e) : null;
    if (pos) msg += ` (line ${pos.line}, column ${pos.column})`;
    this.emit("✖ " + msg);
    if (pos) for (const x of excerpt(this.source, pos.line, pos.column)) this.emit("✖ " + x);
    const frames = String(e?.stack ?? "").split("\n").slice(1).map((f) => f.trim()).filter((f) => f.startsWith("at ") && f.includes(this.scriptName));
    for (const f of frames) this.emit("✖    at " + f.slice(3).replace(/\(?(eval at [^)]*\), )?/, "").replace(/\)$/, ""));
    return msg;
  }

  /** Evaluates a script in the persistent global context (functions stay defined between runs, as in the Mac console). */
  evaluate(code: string, scriptName = "console.js"): ScriptResult {
    this.output = [];
    this.source = code;
    this.scriptName = scriptName.replace(/[^\w.\-]/g, "_") || "console.js";
    const t0 = Date.now();
    let value: any, error: string | null = null;
    try { value = (0, eval)(code + "\n//# sourceURL=" + this.scriptName); }
    catch (e: any) { error = this.report(e); }
    const ms = Date.now() - t0;
    if (!error && code.includes("\n")) this.emit(`✓ finished in ${ms < 10 ? ms.toFixed(1) : Math.round(ms)} ms`);
    const v = !error && value !== undefined ? this.describe(value) : null;
    return { output: this.output, value: v, error };
  }

  /** Calls the handlers of an event; errors are printed ("✖ in <event> handler: …"). */
  fire(event: string, arg: unknown) {
    for (const h of this.handlers.get(event) ?? []) {
      try { h(arg); } catch (e: any) { this.emit(`✖ in ${event} handler: ${e?.message ?? e}`); }
    }
  }

  /** Calls a global function with one argument (buttons of script panels). */
  callGlobal(name: string, arg: unknown) {
    const f = this.g[name];
    if (typeof f !== "function") { this.emit(`✖ No function ${name}() in the script.`); return; }
    try { f(arg); } catch (e: any) { this.report(e); }
  }

  get hooked() { return [...this.handlers.keys()]; }
}

/** Separates a plugin's source from the call appended when one of its commands runs (AppPlugins.callMarker). */
export const PLUGIN_CALL_MARKER = "\n;/*archi-plugin-call*/";

function escapeRe(s: string) { return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }

/** The source a plugin command evaluates: the plugin's script, then a call of its function. */
export function pluginCall(source: string, fn: string, main: string) {
  return source + PLUGIN_CALL_MARKER + `\nif (typeof ${fn} !== 'function') { throw new Error('${main} defines no function ${fn}()'); }\n${fn}();`;
}

// ---- Synchronous channel over a SharedArrayBuffer (worker side and host side) ----

export const CHANNEL_BYTES = 1 << 20;
const HEADER = 16;

/** Worker side: blocks with Atomics.wait until the host has answered (in chunks of up to 1 MB). */
export function syncCall(sab: SharedArrayBuffer, post: (m: any) => void, method: string, params: unknown): any {
  const ctrl = new Int32Array(sab, 0, 4);
  const data = new Uint8Array(sab, HEADER);
  Atomics.store(ctrl, 0, 0);
  post({ type: "call", method, params });
  const parts: Uint8Array[] = [];
  for (;;) {
    Atomics.wait(ctrl, 0, 0);
    const len = Atomics.load(ctrl, 1), more = Atomics.load(ctrl, 2);
    parts.push(data.slice(0, len));
    Atomics.store(ctrl, 0, 0);
    if (!more) break;
    post({ type: "next" });
  }
  let total = 0;
  for (const p of parts) total += p.length;
  const all = new Uint8Array(total);
  let o = 0;
  for (const p of parts) { all.set(p, o); o += p.length; }
  const reply = JSON.parse(new TextDecoder().decode(all));
  if (reply.error) throw reply.error;
  return reply.result;
}

/** Host side: answers a worker's `call` / `next` messages with chunks written into the shared buffer. */
export class SyncHost {
  private pending: Uint8Array | null = null;
  private offset = 0;
  private ctrl: Int32Array;
  private data: Uint8Array;
  constructor(sab: SharedArrayBuffer, private engineCall: (method: string, params: any) => Promise<any>) {
    this.ctrl = new Int32Array(sab, 0, 4);
    this.data = new Uint8Array(sab, HEADER);
  }
  /** Returns true when the message was a channel message. */
  handle(m: any): boolean {
    if (m?.type === "call") {
      this.engineCall(m.method, m.params ?? {}).then((result) => this.reply({ result: result === undefined ? null : result }), (e) => this.reply({ error: { code: e?.code ?? -32000, message: e?.message ?? String(e) } }));
      return true;
    }
    if (m?.type === "next") { this.send(); return true; }
    return false;
  }
  private reply(r: unknown) {
    let s: string;
    try { s = JSON.stringify(r); } catch (e: any) { s = JSON.stringify({ error: { code: -32000, message: String(e?.message ?? e) } }); }
    this.pending = new TextEncoder().encode(s);
    this.offset = 0;
    this.send();
  }
  private send() {
    const p = this.pending;
    if (!p) return;
    const n = Math.min(this.data.length, p.length - this.offset);
    this.data.set(p.subarray(this.offset, this.offset + n), 0);
    this.offset += n;
    const more = this.offset < p.length;
    if (!more) this.pending = null;
    Atomics.store(this.ctrl, 1, n);
    Atomics.store(this.ctrl, 2, more ? 1 : 0);
    Atomics.store(this.ctrl, 0, 1);
    Atomics.notify(this.ctrl, 0);
  }
}

// ---- Event hooks: what changed since the last notification (ScriptEngine.checkEvents) ----

export class ScriptEvents {
  private lastSelection: string | null = null;
  private lastIDs: Set<number> | null = null;
  private lastDirty = false;
  private lastCommand: string | null = null;
  private changeCount = 0;
  hooked: string[] = [];
  busy = false;
  /** `dispatch` runs the handlers in the worker and resolves when they are done. */
  constructor(private call: (m: string, p?: any) => Promise<any>, private dispatch: (events: [string, unknown][]) => Promise<void>) {}

  private async ids(): Promise<Set<number>> {
    const ents = (await this.call("script.call", { fn: "entities", args: [null] })) ?? [];
    const els = (await this.call("script.call", { fn: "elements", args: [null] })) ?? [];
    return new Set<number>([...ents, ...els].map((o: any) => Number(o.id)));
  }

  /** Called with every engine notification of the window. */
  async notify(method: string, params: any) {
    if (!this.hooked.length || this.busy) return;
    const hk = new Set(this.hooked);
    const fire: [string, unknown][] = [];
    try {
      if (method === "prompt") {
        const cmd = params?.active ? String(params.command ?? "") : null;
        if (this.lastCommand && !cmd && hk.has("commandEnded")) fire.push(["commandEnded", this.lastCommand]);
        this.lastCommand = cmd || null;
      } else if (method === "changed") {
        const what: string[] = params?.what ?? [];
        if (what.includes("selection") && hk.has("selectionChanged")) {
          const s = await this.call("select.get");
          const ids = (s?.ids ?? []).map(Number).sort((a: number, b: number) => a - b);
          const key = ids.join(",");
          if (this.lastSelection !== null && key !== this.lastSelection) fire.push(["selectionChanged", ids]);
          this.lastSelection = key;
        }
        if (what.includes("document")) {
          this.changeCount++;
          const info = await this.call("doc.info");
          if (hk.has("documentChanged")) fire.push(["documentChanged", { changeCount: this.changeCount, entities: info?.entities ?? 0, elements: info?.elements ?? 0 }]);
          if (hk.has("elementAdded") || hk.has("elementRemoved")) {
            const now = await this.ids();
            if (this.lastIDs) {
              const added = [...now].filter((i) => !this.lastIDs!.has(i)).sort((a, b) => a - b), removed = [...this.lastIDs].filter((i) => !now.has(i)).sort((a, b) => a - b);
              if (added.length && hk.has("elementAdded")) fire.push(["elementAdded", added]);
              if (removed.length && hk.has("elementRemoved")) fire.push(["elementRemoved", removed]);
            }
            this.lastIDs = now;
          }
          if (this.lastDirty && info && !info.dirty && info.path && hk.has("saved")) fire.push(["saved", info.path]);
          this.lastDirty = !!info?.dirty;
        }
      }
    } catch { /* the engine may be busy or gone */ }
    if (!fire.length) return;
    // Changes made by the handlers themselves do not fire events again: re-baseline after them.
    this.busy = true;
    try { await this.dispatch(fire); await this.baseline(); }
    finally { this.busy = false; }
  }

  /** Baselines when hooks are registered (handlers do not fire for the state they were registered in). */
  async baseline() {
    try {
      const s = await this.call("select.get");
      this.lastSelection = (s?.ids ?? []).map(Number).sort((a: number, b: number) => a - b).join(",");
      const info = await this.call("doc.info");
      this.lastDirty = !!info?.dirty;
      if (this.hooked.includes("elementAdded") || this.hooked.includes("elementRemoved")) this.lastIDs = await this.ids();
    } catch { /* ignore */ }
  }
}
