// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// 3Dconnexion SpaceMouse (SPACEMOUSE, SpaceMouse.swift) through WebHID: the main process lets this window open
// 3Dconnexion / multi-axis controllers without a chooser (src/main/system.ts), the six axes move the 3D camera 60 times
// a second in Object (orbit) or Fly mode, button 1 fits the view (zoom extents), button 2 switches the mode. Settings
// (On/Off, mode, sensitivity, invert zoom, dominant axis) are kept per user like the Mac's UserDefaults and told to the
// engine with ui.prefs spaceMouse.* so SPACEMOUSE Status reports the same line as on the Mac.
import type { App } from "../app";
import { applyMotion, motion, isZero, defaultConfig, reportLayout, applyReport, emptyState, isSpaceMouse, HID_FILTERS, type SpaceMouseConfig, type ReportLayout, type HidState } from "./spacemouse-math";

const KEY = "archi.spaceMouse";
function load(): { enabled: boolean; config: SpaceMouseConfig } {
  const c = defaultConfig();
  let enabled = true;
  try {
    const s = JSON.parse(localStorage.getItem(KEY) ?? "{}");
    if (typeof s.enabled === "boolean") enabled = s.enabled;
    if (s.mode === "Object" || s.mode === "Fly") c.mode = s.mode;
    if (Number.isFinite(s.sensitivity)) c.sensitivity = Math.min(10, Math.max(0.05, s.sensitivity));
    c.invertZoom = !!s.invertZoom; c.dominant = !!s.dominant;
  } catch {}
  return { enabled, config: c };
}

export interface SpaceMouseView { getCamera(): any; setCamera(c: any, animated?: boolean): void; zoomExtents(): void }

export class SpaceMouseController {
  enabled: boolean;
  config: SpaceMouseConfig;
  devices: { device: any; name: string; layout: ReportLayout }[] = [];
  state: HidState = emptyState();
  private timer: number | null = null;
  private last = performance.now();
  private prevButtons = new Set<number>();

  constructor(private app: App, private view: () => SpaceMouseView | null) {
    const s = load();
    this.enabled = s.enabled; this.config = s.config;
  }

  get hid(): any { return (navigator as any).hid ?? null; }
  get available() { return !!this.hid; }
  get running() { return this.enabled && this.available; }

  save() {
    try { localStorage.setItem(KEY, JSON.stringify({ enabled: this.enabled, mode: this.config.mode, sensitivity: this.config.sensitivity, invertZoom: this.config.invertZoom, dominant: this.config.dominant })); } catch {}
    void this.app.tryCall("ui.prefs", { values: {
      "spaceMouse.enabled": this.enabled ? "1" : "0", "spaceMouse.mode": this.config.mode, "spaceMouse.sensitivity": String(this.config.sensitivity),
      "spaceMouse.available": this.available ? "1" : "0", "spaceMouse.devices": this.devices.map((d) => d.name).join("\n"),
    } });
  }

  /** SPACEMOUSE answered by the engine: {enabled, mode, sensitivity}. */
  async set(p: { enabled?: boolean; mode?: string; sensitivity?: number }) {
    if (typeof p.enabled === "boolean") this.enabled = p.enabled;
    if (p.mode === "Object" || p.mode === "Fly") this.config.mode = p.mode;
    if (Number.isFinite(p.sensitivity)) this.config.sensitivity = Math.min(10, Math.max(0.05, Number(p.sensitivity)));
    if (this.enabled) await this.start(true); else this.stop();
    this.save();
  }

  async start(ask = false) {
    const hid = this.hid;
    if (!hid || !this.enabled) { this.save(); return; }
    if (!(this as any).listening) {
      (this as any).listening = true;
      hid.addEventListener?.("connect", (e: any) => { if (this.enabled && isSpaceMouse(e.device)) void this.open(e.device); });
      hid.addEventListener?.("disconnect", (e: any) => { this.devices = this.devices.filter((d) => d.device !== e.device); this.save(); });
    }
    let list: any[] = [];
    try { list = (await hid.getDevices()).filter(isSpaceMouse); } catch {}
    if (!list.length && ask) { try { list = (await hid.requestDevice({ filters: HID_FILTERS })).filter(isSpaceMouse); } catch {} }
    for (const d of list) await this.open(d);
    this.save();
  }

  private async open(device: any) {
    if (this.devices.some((d) => d.device === device)) return;
    try { if (!device.opened) await device.open(); } catch { return; }
    const entry = { device, name: String(device.productName || "Multi-axis controller"), layout: reportLayout(device.collections ?? []) };
    if (this.devices.some((d) => d.name === entry.name && d.device === device)) return;
    this.devices.push(entry);
    device.addEventListener("inputreport", (e: any) => { if (this.enabled) applyReport(this.state, entry.layout, e.reportId, e.data); this.buttons(); });
    this.last = performance.now();
    if (this.timer === null) this.timer = setInterval(() => this.tick(), 1000 / 60) as unknown as number;
    this.save();
  }

  stop() {
    if (this.timer !== null) { clearInterval(this.timer); this.timer = null; }
    for (const d of this.devices) { try { void d.device.close(); } catch {} }
    this.devices = []; this.state = emptyState(); this.prevButtons.clear();
  }

  /** Button 1 fits the view, button 2 switches Object / Fly (pressed edges only). */
  private buttons() {
    const now = this.state.buttons;
    if (now.has(1) && !this.prevButtons.has(1)) { const v = this.view(); if (v && this.is3D()) v.zoomExtents(); }
    if (now.has(2) && !this.prevButtons.has(2)) { this.config.mode = this.config.mode === "Object" ? "Fly" : "Object"; this.save(); }
    this.prevButtons = new Set(now);
  }

  private is3D() { return this.app.mode === "3D" || this.app.mode === "Split"; }

  tick(now = performance.now()) {
    const dt = Math.min((now - this.last) / 1000, 0.1);
    this.last = now;
    const m = motion(this.state.axes, this.config, dt);
    const v = this.view();
    if (isZero(m) || !v || !this.is3D()) return;
    // The 3D view works in metres: the Mac's 50 mm minimum distance is 0.05 m.
    v.setCamera(applyMotion(m, v.getCamera(), this.config.mode, 0.05), false);
  }

  statusLine() {
    const dev = this.devices.length ? this.devices.map((d) => d.name).join(", ") : "none connected";
    const s = Number(this.config.sensitivity.toFixed(2));
    return `SpaceMouse ${this.running ? "on" : "off"}, ${this.config.mode} mode, sensitivity ${s}; devices: ${dev}.`;
  }
}
