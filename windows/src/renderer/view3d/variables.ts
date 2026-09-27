// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Drawing variables of the 3D view, same text format as the Mac (Viewport3DExtras.swift SectionBox / SectionPlane).
import type { SectionBox, SectionPlane } from "./renderer";
import type { V3 } from "./math";

const fmt = (v: number, d: number) => String(Number(v.toFixed(d)));

/** SECTIONBOX = "on;x0,y0,z0,x1,y1,z1" (model units). */
export function parseSectionBox(s: string | null | undefined): SectionBox | null {
  if (!s) return null;
  const parts = s.split(";");
  if (parts.length !== 2) return null;
  const n = parts[1].split(",").map(Number);
  if (n.length !== 6 || !n.every(Number.isFinite)) return null;
  return { on: parts[0] === "on", min: [Math.min(n[0], n[3]), Math.min(n[1], n[4]), Math.min(n[2], n[5])], max: [Math.max(n[0], n[3]), Math.max(n[1], n[4]), Math.max(n[2], n[5])] };
}
export function formatSectionBox(b: SectionBox): string {
  return (b.on ? "on" : "off") + ";" + [...b.min, ...b.max].map((v) => fmt(v, 1)).join(",");
}

/** SECTIONPLANE = "on;px,py,pz;nx,ny,nz". */
export function parseSectionPlane(s: string | null | undefined): SectionPlane | null {
  if (!s) return null;
  const parts = s.split(";");
  if (parts.length !== 3) return null;
  const p = parts[1].split(",").map(Number), n = parts[2].split(",").map(Number);
  if (p.length !== 3 || n.length !== 3 || ![...p, ...n].every(Number.isFinite)) return null;
  const l = Math.hypot(n[0], n[1], n[2]);
  if (l < 1e-9) return null;
  return { on: parts[0] === "on", point: p as V3, normal: [n[0] / l, n[1] / l, n[2] / l] };
}
export function formatSectionPlane(p: SectionPlane): string {
  return (p.on ? "on" : "off") + ";" + p.point.map((v) => fmt(v, 3)).join(",") + ";" + p.normal.map((v) => fmt(v, 6)).join(",");
}
