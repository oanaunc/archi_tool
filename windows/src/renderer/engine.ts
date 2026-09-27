// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Engine access for the renderer: the Electron bridge (window.archi) or, in a plain browser, the fixture engine.
import type { ArchiBridge, Notification } from "../shared/protocol";
import { FakeEngine } from "./fake-engine";

export interface Engine {
  call(method: string, params?: unknown): Promise<any>;
  onNotify(cb: (n: Notification) => void): void;
  readonly native: ArchiBridge | null;
  readonly kind: "electron" | "fixtures";
}

class BridgeEngine implements Engine {
  readonly kind = "electron" as const;
  constructor(readonly native: ArchiBridge) {}
  call(method: string, params?: unknown) { return this.native.rpc(method, params ?? {}); }
  onNotify(cb: (n: Notification) => void) { this.native.onNotify(cb); }
}

export function createEngine(): Engine {
  const w = window as any;
  if (w.archi && typeof w.archi.rpc === "function") return new BridgeEngine(w.archi as ArchiBridge);
  const q = new URLSearchParams(location.search);
  return new FakeEngine(q.get("fixtures") || "fixtures/engine");
}
