// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Progress of long jobs for the status bar (ProgressCenter / ProgressStatusView, AppNavigation.swift): begin, update
// with a fraction and detail, cancel and end. Engine calls that take longer than half a second (a command, an import or
// export, opening a drawing) show an indeterminate job named after them, with Cancel sending Escape.
export interface Job { id: number; title: string; fraction: number | null; detail: string; cancelled: boolean; onCancel?: () => void }

class ProgressCenter {
  jobs: Job[] = [];
  private next = 1;
  private listeners: (() => void)[] = [];
  on(cb: () => void) { this.listeners.push(cb); }
  private emit() { for (const l of this.listeners) l(); }
  begin(title: string, indeterminate = false, onCancel?: () => void): number {
    const id = this.next++;
    this.jobs.push({ id, title, fraction: indeterminate ? null : 0, detail: "", cancelled: false, onCancel });
    this.emit();
    return id;
  }
  update(id: number, fraction: number | null, detail?: string) {
    const j = this.jobs.find((x) => x.id === id);
    if (!j) return;
    j.fraction = fraction === null ? null : Math.min(Math.max(fraction, 0), 1);
    if (detail !== undefined) j.detail = detail;
    this.emit();
  }
  cancel(id: number) { const j = this.jobs.find((x) => x.id === id); if (j && !j.cancelled) { j.cancelled = true; j.onCancel?.(); this.emit(); } }
  isCancelled(id: number) { return this.jobs.find((x) => x.id === id)?.cancelled ?? true; }
  end(id: number) { const n = this.jobs.length; this.jobs = this.jobs.filter((x) => x.id !== id); if (n !== this.jobs.length) this.emit(); }
  get current(): Job | null { return this.jobs[this.jobs.length - 1] ?? null; }
  /** Runs `count` steps with progress; returns the number completed (fewer when cancelled). */
  async run(title: string, count: number, step: (i: number) => Promise<void> | void): Promise<number> {
    const id = this.begin(title);
    try {
      for (let i = 0; i < count; i++) {
        if (this.isCancelled(id)) return i;
        this.update(id, i / Math.max(count, 1), `${i + 1} of ${count}`);
        await step(i);
        await new Promise((r) => setTimeout(r, 0));
      }
      this.update(id, 1);
      return count;
    } finally { this.end(id); }
  }
}
export const progress = new ProgressCenter();
(window as any).archiProgress = progress;

const TRACKED: Record<string, string> = { "command.run": "", "input.text": "", "input.key": "", "input.point": "", "doc.open": "Opening", "doc.save": "Saving",
  "file.export": "Exporting", "file.import": "Importing", "macro.run": "", "assistant.apply": "Applying the assistant's commands", "content.add": "Adding definitions" };

/** Wraps the engine so slow calls show in the status bar. */
export function trackEngine(engine: { call(m: string, p?: unknown): Promise<any> }, title: () => string, cancel: () => void, delay = 500) {
  const orig = engine.call.bind(engine);
  (engine as any).call = (method: string, params?: unknown) => {
    const label = TRACKED[method];
    if (label === undefined) return orig(method, params);
    let id = 0;
    const timer = setTimeout(() => { id = progress.begin(label || title(), true, cancel); }, delay);
    return orig(method, params).finally(() => { clearTimeout(timer); if (id) progress.end(id); });
  };
}
