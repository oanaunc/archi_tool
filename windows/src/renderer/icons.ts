// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// SF Symbol names (as used by the Mac app) rendered with the closest Lucide icon (ISC licence, tools/sf-to-lucide.mjs).
import data from "./data/icons.generated.json";

const icons = (data as any).icons as Record<string, { lucide: string; nodes: [string, Record<string, string>][] }>;
const SVGNS = "http://www.w3.org/2000/svg";

export function icon(sf: string, size = 16, strokeWidth = 1.6): SVGSVGElement {
  const svg = document.createElementNS(SVGNS, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("width", String(size));
  svg.setAttribute("height", String(size));
  svg.setAttribute("fill", "none");
  svg.setAttribute("stroke", "currentColor");
  svg.setAttribute("stroke-width", String(strokeWidth));
  svg.setAttribute("stroke-linecap", "round");
  svg.setAttribute("stroke-linejoin", "round");
  svg.classList.add("icon");
  const def = icons[sf] ?? icons["terminal"];
  if (def) {
    svg.dataset.sf = sf; svg.dataset.lucide = def.lucide;
    for (const [tag, attrs] of def.nodes) {
      const el = document.createElementNS(SVGNS, tag);
      for (const [k, v] of Object.entries(attrs)) el.setAttribute(k.replace(/[A-Z]/g, (m) => "-" + m.toLowerCase()), String(v));
      svg.appendChild(el);
    }
  }
  return svg;
}
export function hasIcon(sf: string) { return sf in icons; }
