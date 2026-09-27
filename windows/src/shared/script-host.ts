// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Host side of a window's script worker: starts the worker with its SharedArrayBuffer channel, answers its engine
// requests, runs evaluations one at a time, streams output lines, feeds the event hooks and restarts the context
// (the console's reset button). Used by the Electron main process and by the renderer in a browser.
import { CHANNEL_BYTES, ScriptEvents, SyncHost, type ScriptResult } from "./script-runtime";

export interface WorkerLike { post(m: any): void; onMessage(cb: (m: any) => void): void; terminate(): void }

export interface ScriptHostOptions {
  makeWorker: (sab: SharedArrayBuffer) => WorkerLike;
  engineCall: (method: string, params: any) => Promise<any>;
  onLine: (text: string) => void;
  onPanel: (spec: any) => void;
}

export class ScriptHost {
  private worker: WorkerLike | null = null;
  private sync: SyncHost | null = null;
  private seq = 0;
  private waiting = new Map<number, (m: any) => void>();
  private queue: Promise<unknown> = Promise.resolve();
  readonly events: ScriptEvents;

  constructor(private o: ScriptHostOptions) {
    this.events = new ScriptEvents((m, p) => o.engineCall(m, p ?? {}), (events) => this.request({ type: "fire", events }).then(() => undefined));
  }

  private start(): WorkerLike {
    if (this.worker) return this.worker;
    const sab = new SharedArrayBuffer(CHANNEL_BYTES + 16);
    const w = this.o.makeWorker(sab);
    this.sync = new SyncHost(sab, this.o.engineCall);
    w.onMessage((m) => this.onMessage(m));
    w.post({ type: "init", sab });
    this.worker = w;
    return w;
  }

  private onMessage(m: any) {
    if (this.sync?.handle(m)) return;
    switch (m?.type) {
      case "line": this.o.onLine(String(m.text)); break;
      case "panel": this.o.onPanel(m.spec); break;
      case "hooks":
        this.events.hooked = m.events ?? [];
        if (this.events.hooked.length) this.events.baseline();
        break;
      case "result": case "fired": { const cb = this.waiting.get(m.id); this.waiting.delete(m.id); cb?.(m); break; }
    }
  }

  private request(m: any): Promise<any> {
    const w = this.start();
    const id = ++this.seq;
    return new Promise((resolve) => { this.waiting.set(id, resolve); w.post({ ...m, id }); });
  }

  /** Evaluates a script (queued: one evaluation at a time per window). */
  evaluate(code: string, name = "console.js"): Promise<ScriptResult> {
    const run = this.queue.then(() => this.request({ type: "eval", code, name }).then((m) => ({ output: m.output ?? [], value: m.value ?? null, error: m.error ?? null })));
    this.queue = run.catch(() => undefined);
    return run;
  }

  callGlobal(name: string, arg: unknown) { this.queue = this.queue.then(() => this.request({ type: "callGlobal", name, arg })).catch(() => undefined); }

  /** Engine notifications of the window (for archi.on hooks). */
  notify(method: string, params: any) { if (this.worker) this.events.notify(method, params); }

  /** New JavaScript context (globals and hooks are dropped). */
  reset() {
    this.worker?.terminate();
    this.worker = null;
    this.sync = null;
    for (const cb of this.waiting.values()) cb({ output: [], value: null, error: "The JavaScript context was reset." });
    this.waiting.clear();
    this.events.hooked = [];
    this.queue = Promise.resolve();
  }

  dispose() { this.reset(); }
}
