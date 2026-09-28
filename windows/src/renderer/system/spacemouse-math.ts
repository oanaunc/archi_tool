// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// SpaceMouse maths, ported from SpaceMouse.swift: raw axes → camera motion (dead zone, quadratic response, dominant
// axis, sensitivity), the Object (orbit) and Fly camera moves, and the HID report layout (generic desktop X…Rz =
// usages 0x30…0x35, buttons page 9) read from WebHID's report descriptors, with the classic 3Dconnexion reports as a
// fallback (report 1 translation, 2 rotation, 3 buttons; newer devices send all six axes in report 1).
import type { V3 } from "../view3d/math";
import { add, sub, scale, len, norm, cross, dot } from "../view3d/math";

export type SpaceMouseMode = "Object" | "Fly";
export interface SpaceMouseConfig { sensitivity: number; deadzone: number; mode: SpaceMouseMode; invertZoom: boolean; dominant: boolean }
export const defaultConfig = (): SpaceMouseConfig => ({ sensitivity: 1, deadzone: 0.06, mode: "Object", invertZoom: false, dominant: false });

/** Camera motion for one tick: pan (right, up, forward as fractions of the view distance) and turns (radians). */
export interface Motion { right: number; up: number; forward: number; yaw: number; pitch: number }
export const isZero = (m: Motion) => m.right === 0 && m.up === 0 && m.forward === 0 && m.yaw === 0 && m.pitch === 0;

/** Raw axis values (±350 typical full deflection) → motion for `dt` seconds. HID axes: X right, Y towards the user,
 *  Z down; Rx tilt, Ry roll (unused), Rz spin. */
export function motion(a: number[], c: SpaceMouseConfig, dt: number): Motion {
  const m: Motion = { right: 0, up: 0, forward: 0, yaw: 0, pitch: 0 };
  if (a.length < 6) return m;
  let v = a.map((x) => {
    const n = Math.max(-1, Math.min(1, x / 350));
    const dz = c.deadzone;
    if (!(Math.abs(n) > dz)) return 0;
    const s = (Math.abs(n) - dz) / (1 - dz);
    return (n < 0 ? -1 : 1) * s * s; // quadratic response: fine control near the centre
  });
  if (c.dominant) {
    let i = 0;
    for (let k = 1; k < v.length; k++) if (Math.abs(v[k]) > Math.abs(v[i])) i = k;
    v = v.map((x, k) => (k === i ? x : 0));
  }
  const k = c.sensitivity * dt;
  m.right = v[0] * 1.2 * k;
  m.forward = (c.invertZoom ? v[1] : -v[1]) * 1.5 * k;
  m.up = -v[2] * 1.2 * k;
  m.pitch = -v[3] * 1.6 * k;
  m.yaw = -v[5] * 1.6 * k;
  for (const key of Object.keys(m) as (keyof Motion)[]) if (Object.is(m[key], -0)) m[key] = 0;
  return m;
}

export interface Cam { eye: V3; target: V3 }

const rotZ = (v: V3, a: number): V3 => [v[0] * Math.cos(a) - v[1] * Math.sin(a), v[0] * Math.sin(a) + v[1] * Math.cos(a), v[2]];
const rotAxis = (v: V3, k: V3, a: number): V3 => add(add(scale(v, Math.cos(a)), scale(cross(k, v), Math.sin(a))), scale(k, dot(k, v) * (1 - Math.cos(a))));
const pitchOK = (d: V3) => Math.abs(norm(d)[2]) < 0.985;

/** Moves a camera (Z up). Object mode orbits and zooms about the target; Fly mode moves the eye. `minDistance` is
 *  the Mac's 50 mm in the camera's units. */
export function applyMotion<T extends Cam>(m: Motion, cam: T, mode: SpaceMouseMode, minDistance = 50): T {
  if (isZero(m)) return cam;
  let eye = cam.eye, target = cam.target;
  let fwd = sub(target, eye);
  const dist = Math.max(len(fwd), minDistance / 50);
  fwd = scale(fwd, 1 / dist);
  let right = cross(fwd, [0, 0, 1]);
  if (len(right) < 1e-6) right = [1, 0, 0];
  right = norm(right);
  const up = norm(cross(right, fwd));
  if (mode === "Object") {
    const pan = add(scale(right, m.right * dist), scale(up, m.up * dist));
    eye = add(eye, pan); target = add(target, pan);
    const newDist = Math.max(dist * (1 - m.forward), minDistance);
    let off = scale(norm(sub(eye, target)), newDist);
    off = rotZ(off, m.yaw);
    const o2 = rotAxis(off, right, m.pitch);
    if (pitchOK(o2)) off = o2;
    eye = add(target, off);
  } else {
    const move = add(add(scale(right, m.right * dist), scale(up, m.up * dist)), scale(fwd, m.forward * dist));
    eye = add(eye, move);
    let d = rotZ(sub(target, sub(eye, move)), m.yaw);
    const d2 = rotAxis(d, right, m.pitch);
    if (pitchOK(d2)) d = d2;
    target = add(eye, scale(norm(d), dist));
  }
  return { ...cam, eye, target };
}

// ---- HID reports ----

export interface HidField { usage: number; bitOffset: number; bitSize: number; signed: boolean }
/** Report id → the fields of that input report (WebHID HIDCollectionInfo, usages as (page << 16) | usage). */
export type ReportLayout = Map<number, HidField[]>;
export const AXIS_USAGES = [0x10030, 0x10031, 0x10032, 0x10033, 0x10034, 0x10035];
export const BUTTON_PAGE = 0x9;

export function reportLayout(collections: any[]): ReportLayout {
  const out: ReportLayout = new Map();
  const walk = (cs: any[]) => {
    for (const c of cs ?? []) {
      for (const r of c.inputReports ?? []) {
        const fields = out.get(r.reportId ?? 0) ?? [];
        let offset = fields.length ? Math.max(...fields.map((f) => f.bitOffset + f.bitSize)) : 0;
        for (const it of r.items ?? []) {
          const size = Number(it.reportSize ?? 0), count = Number(it.reportCount ?? 0);
          if (!it.isConstant) {
            for (let j = 0; j < count; j++) {
              let usage: number | undefined;
              if (it.isRange) { const u = Number(it.usageMinimum) + j; usage = u <= Number(it.usageMaximum) ? u : undefined; }
              else usage = it.usages?.[j] ?? it.usages?.[it.usages.length - 1];
              if (usage !== undefined) fields.push({ usage, bitOffset: offset + j * size, bitSize: size, signed: Number(it.logicalMinimum ?? 0) < 0 });
            }
          }
          offset += size * count;
        }
        out.set(r.reportId ?? 0, fields);
      }
      walk(c.children ?? []);
    }
  };
  walk(collections);
  return out;
}

function readBits(d: DataView, offset: number, size: number, signed: boolean): number {
  let v = 0;
  for (let b = 0; b < size; b++) {
    const bit = offset + b, byte = bit >> 3;
    if (byte >= d.byteLength) break;
    if ((d.getUint8(byte) >> (bit & 7)) & 1) v += 2 ** b;
  }
  if (signed && size > 1 && v >= 2 ** (size - 1)) v -= 2 ** size;
  return v;
}

export interface HidState { axes: number[]; buttons: Set<number> }
export const emptyState = (): HidState => ({ axes: [0, 0, 0, 0, 0, 0], buttons: new Set() });

/** Applies one input report to the axis / button state (the Mac's handle(page:usage:value:)). */
export function applyReport(state: HidState, layout: ReportLayout, reportId: number, data: DataView) {
  const fields = layout.get(reportId);
  if (fields && fields.some((f) => AXIS_USAGES.includes(f.usage) || f.usage >> 16 === BUTTON_PAGE)) {
    const pressed = new Set<number>();
    let hasButtons = false;
    for (const f of fields) {
      const i = AXIS_USAGES.indexOf(f.usage);
      if (i >= 0) state.axes[i] = readBits(data, f.bitOffset, f.bitSize, f.signed);
      else if (f.usage >> 16 === BUTTON_PAGE) { hasButtons = true; if (readBits(data, f.bitOffset, f.bitSize, false)) pressed.add(f.usage & 0xffff); }
    }
    if (hasButtons) state.buttons = pressed;
    return;
  }
  // Classic 3Dconnexion reports.
  const i16 = (k: number) => (data.byteLength >= 2 * k + 2 ? data.getInt16(2 * k, true) : 0);
  if (reportId === 1) { for (let k = 0; k < 3; k++) state.axes[k] = i16(k); if (data.byteLength >= 12) for (let k = 3; k < 6; k++) state.axes[k] = i16(k); }
  else if (reportId === 2) { for (let k = 0; k < 3; k++) state.axes[3 + k] = i16(k); }
  else if (reportId === 3) {
    const pressed = new Set<number>();
    for (let b = 0; b < data.byteLength * 8; b++) if ((data.getUint8(b >> 3) >> (b & 7)) & 1) pressed.add(b + 1);
    state.buttons = pressed;
  }
}

/** WebHID filters: 3Dconnexion, and Logitech-made 3Dconnexion multi-axis controllers (SpaceMouse.swift matching). */
export const HID_FILTERS = [{ vendorId: 0x256f }, { vendorId: 0x046d, usagePage: 0x01, usage: 0x08 }, { usagePage: 0x01, usage: 0x08 }];
export function isSpaceMouse(d: { vendorId?: number; collections?: any[] }): boolean {
  if (d.vendorId === 0x256f) return true;
  return (d.collections ?? []).some((c: any) => c.usagePage === 0x01 && c.usage === 0x08);
}
