// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// SF Symbols of the output windows that the generated icon table does not have, drawn as Lucide (ISC) paths.
import { icon, hasIcon } from "../icons";

const SVGNS = "http://www.w3.org/2000/svg";
const EXTRA: Record<string, [string, Record<string, string>][]> = {
  hourglass: [["path", { d: "M5 22h14" }], ["path", { d: "M5 2h14" }], ["path", { d: "M17 22v-4.172a2 2 0 0 0-.586-1.414L12 12l-4.414 4.414A2 2 0 0 0 7 17.828V22" }], ["path", { d: "M7 2v4.172a2 2 0 0 0 .586 1.414L12 12l4.414-4.414A2 2 0 0 0 17 6.172V2" }]],
  "exclamationmark.triangle.fill": [["path", { d: "m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3", fill: "currentColor" }], ["path", { d: "M12 9v4", stroke: "#26272B" }], ["path", { d: "M12 17h.01", stroke: "#26272B" }]],
  "play.fill": [["polygon", { points: "6 3 20 12 6 21 6 3", fill: "currentColor" }]],
  "pause.fill": [["rect", { x: "6", y: "4", width: "4", height: "16", rx: "1", fill: "currentColor" }], ["rect", { x: "14", y: "4", width: "4", height: "16", rx: "1", fill: "currentColor" }]],
  "diamond.fill": [["path", { d: "M2.7 10.3a2.41 2.41 0 0 0 0 3.41l7.59 7.59a2.41 2.41 0 0 0 3.41 0l7.59-7.59a2.41 2.41 0 0 0 0-3.41L13.7 2.71a2.41 2.41 0 0 0-3.41 0z", fill: "currentColor" }]],
  xmark: [["path", { d: "M18 6 6 18" }], ["path", { d: "m6 6 12 12" }]],
};

export function sym(sf: string, size = 12, stroke = 1.8): SVGSVGElement {
  if (hasIcon(sf) || !EXTRA[sf]) return icon(sf, size, stroke);
  const svg = document.createElementNS(SVGNS, "svg");
  for (const [k, v] of Object.entries({ viewBox: "0 0 24 24", width: String(size), height: String(size), fill: "none", stroke: "currentColor", "stroke-width": String(stroke), "stroke-linecap": "round", "stroke-linejoin": "round" })) svg.setAttribute(k, v);
  svg.classList.add("icon");
  svg.dataset.sf = sf;
  for (const [tag, attrs] of EXTRA[sf]) { const el = document.createElementNS(SVGNS, tag); for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v); svg.append(el); }
  return svg;
}
