// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Mechanism playback on the plan (ArchiApp/AppCommandsRound11.swift MechanismPlayback, MECHANISMPLAY): the poses the
// engine simulated (draw items in the accent colour) played as an overlay Once, in a Loop or Bounce at the given frame
// rate, at most 20 loops; the drawing is not changed. The engine's `host` action {"action":"canvas","op":"mechanismPlay"}.
import { decodeItem, type Item } from "./drawitems";

export type PlaybackMode = "Once" | "Loop" | "Bounce";
export const MAX_LOOPS = 20;

/** Pose shown at a tick (null = finished), as MechanismPlayback.frame. */
export function mechanismFrame(tick: number, n: number, mode: PlaybackMode): number | null {
  if (n <= 0 || tick < 0) return null;
  switch (mode) {
    case "Once": return tick < n ? tick : null;
    case "Loop": return tick < n * MAX_LOOPS ? tick % n : null;
    case "Bounce": {
      if (n <= 1) return tick < MAX_LOOPS ? 0 : null;
      const period = 2 * (n - 1);
      if (tick >= period * MAX_LOOPS) return null;
      const t = tick % period;
      return t < n ? t : period - t;
    }
  }
}

export class MechanismPlayer {
  readonly poses: Item[][];
  tick = 0;
  private timer: ReturnType<typeof setInterval> | null = null;
  constructor(poses: unknown[][], readonly mode: PlaybackMode, readonly fps: number, private repaint: () => void, private finished: () => void) {
    this.poses = poses.map((p) => (p ?? []).map(decodeItem).filter(Boolean) as Item[]);
  }
  get current(): Item[] | null {
    const i = mechanismFrame(this.tick, this.poses.length, this.mode);
    return i == null ? null : this.poses[i];
  }
  start() {
    this.stop(false);
    this.timer = setInterval(() => {
      this.tick += 1;
      if (this.current == null) this.stop(true); else this.repaint();
    }, 1000 / Math.max(1, Math.min(120, this.fps)));
    this.repaint();
  }
  stop(done: boolean) {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    this.repaint();
    if (done) this.finished();
  }
}
