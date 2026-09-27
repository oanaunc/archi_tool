// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// JSON-RPC 2.0 client for one archi-engine process (newline-delimited JSON over stdin/stdout).
import { spawn, ChildProcessWithoutNullStreams } from "node:child_process";
import { EventEmitter } from "node:events";

export interface RpcError { code: number; message: string; data?: unknown }

export class EngineProcess extends EventEmitter {
  private proc: ChildProcessWithoutNullStreams | null = null;
  private nextId = 1;
  private pending = new Map<number, { resolve: (v: any) => void; reject: (e: any) => void; method: string }>();
  private buffer = "";
  private stderrTail: string[] = [];
  exited = false;

  constructor(private exe: string, private args: string[] = [], private cwd?: string) { super(); }

  start(): void {
    this.proc = spawn(this.exe, this.args, { cwd: this.cwd, stdio: ["pipe", "pipe", "pipe"], windowsHide: true });
    this.proc.stdout.setEncoding("utf8");
    this.proc.stdout.on("data", (chunk: string) => this.onData(chunk));
    this.proc.stderr.setEncoding("utf8");
    this.proc.stderr.on("data", (s: string) => {
      this.stderrTail.push(...s.split(/\r?\n/).filter(Boolean));
      if (this.stderrTail.length > 50) this.stderrTail.splice(0, this.stderrTail.length - 50);
      this.emit("stderr", s);
    });
    this.proc.on("error", (e) => this.fail(`Could not start the engine (${this.exe}): ${e.message}`));
    this.proc.on("exit", (code, signal) => this.fail(`The engine stopped (code ${code ?? "?"}${signal ? ", " + signal : ""}). ${this.stderrTail.slice(-3).join(" ")}`));
  }

  private fail(message: string) {
    if (this.exited) return;
    this.exited = true;
    for (const p of this.pending.values()) p.reject({ code: -32000, message });
    this.pending.clear();
    this.emit("exit", message);
  }

  private onData(chunk: string) {
    this.buffer += chunk;
    let nl: number;
    while ((nl = this.buffer.indexOf("\n")) >= 0) {
      const line = this.buffer.slice(0, nl).trim();
      this.buffer = this.buffer.slice(nl + 1);
      if (!line) continue;
      let msg: any;
      try { msg = JSON.parse(line); } catch { this.emit("stderr", `unparsable engine output: ${line.slice(0, 200)}`); continue; }
      if (msg.id !== undefined && msg.id !== null && (("result" in msg) || ("error" in msg))) {
        const p = this.pending.get(msg.id);
        if (!p) continue;
        this.pending.delete(msg.id);
        if (msg.error) p.reject(msg.error); else p.resolve(msg.result);
      } else if (msg.method) {
        this.emit("notification", { method: msg.method, params: msg.params });
      }
    }
  }

  call(method: string, params: unknown = {}): Promise<any> {
    if (this.exited || !this.proc) return Promise.reject({ code: -32000, message: "The engine is not running." });
    const id = this.nextId++;
    const line = JSON.stringify({ jsonrpc: "2.0", id, method, params: params ?? {} }) + "\n";
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject, method });
      this.proc!.stdin.write(line, "utf8");
    });
  }

  stop(): void {
    if (!this.proc || this.exited) return;
    try { this.proc.stdin.end(); } catch {}
    const p = this.proc;
    setTimeout(() => { if (!this.exited) try { p.kill(); } catch {} }, 1500);
  }
}
