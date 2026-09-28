// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Layer / level / colour / linetype / lineweight / dimension style / visual style drop-downs (RibbonView.swift, shared with the status bar).
import type { App } from "../app";
import { h, clear } from "../dom";
import { icon } from "../icons";
import { showMenu, help, MenuItem } from "./menu";

const BASIC: [string, string, string][] = [["Red", "1", "#FF0000"], ["Yellow", "2", "#FFFF00"], ["Green", "3", "#00FF00"], ["Cyan", "4", "#00FFFF"], ["Blue", "5", "#0000FF"],
  ["Magenta", "6", "#FF00FF"], ["White", "7", "#FFFFFF"], ["Gray", "8", "#808080"], ["Light Gray", "9", "#C0C0C0"], ["Orange", "30", "#FF7F00"], ["Brown", "34", "#7F3F00"]];
export const LINEWEIGHTS = [0, 0.05, 0.09, 0.13, 0.15, 0.18, 0.2, 0.25, 0.3, 0.35, 0.4, 0.5, 0.53, 0.6, 0.7, 0.8, 0.9, 1.0, 1.06, 1.2, 1.4, 1.58, 2.0, 2.11];
const VISUAL_STYLES = ["Realistic", "Shaded", "Shaded with Edges", "Conceptual", "Hidden", "Wireframe", "X-Ray", "Sketchy"];

function field(width: number, helpText: string, build: (el: HTMLElement) => void, menu: () => MenuItem[], app: App, events: Parameters<App["on"]>[0]) {
  const el = h("button", { class: "dropfield", style: { width: width + "px" } });
  const render = () => { clear(el); build(el); el.append(icon("chevron.down", 10, 2)); (el.lastChild as Element).classList.add("chev"); };
  render();
  app.on(events, render);
  el.addEventListener("click", () => showMenu(menu(), el));
  help(el, helpText);
  return el;
}
function layerColor(app: App, name: string) { return app.layers.layers.find((l: any) => l.name === name)?.color ?? "#FFFFFF"; }

export function layerDropdown(app: App, width: number) {
  return field(width, "Current layer — choose to make another layer current", (el) => {
    const cur = app.sysvars.CLAYER ?? app.layers.current ?? "0";
    el.append(h("span", { class: "swatch", style: { background: layerColor(app, cur) } }), h("span", { class: "t", text: cur }));
  }, () => app.layers.layers.map((l: any) => ({
    title: l.name + (l.on === false || l.visible === false ? "  (off)" : "") + (l.frozen ? "  (frozen)" : "") + (l.locked ? "  (locked)" : ""), swatch: l.color,
    action: () => app.selection.ids.length ? app.call("panel.set", { panel: "properties", key: "layer", value: l.name }).then(() => app.refresh(["drawing", "properties"])) : app.setVar("CLAYER", l.name),
  })), app, ["layers", "sysvars", "selection"]);
}
export function levelDropdown(app: App, width: number) {
  return field(width, "Current level (new building elements go here)", (el) => {
    el.append(icon("building.2", 12), h("span", { class: "t", text: app.info?.currentLevel ?? app.sysvars.CLEVEL ?? "Level" }));
  }, () => [...(app.info?.levels ?? [])].sort((a, b) => b.elevation - a.elevation).map((l) => ({
    title: `${l.name}  (${Math.round(l.elevation)})`, checked: l.name === app.info?.currentLevel,
    action: () => app.call("panel.set", { panel: "levels", key: "current", value: l.name }).catch(() => app.setVar("CLEVEL", l.name)).then(() => app.refresh(["document", "drawing", "levels"])),
  })), app, ["doc", "sysvars"]);
}
function colorHex(v: string, app: App) {
  if (!v || /^bylayer$/i.test(v)) return layerColor(app, app.sysvars.CLAYER ?? "0");
  if (/^byblock$/i.test(v)) return "#FFFFFF";
  const b = BASIC.find((x) => x[1] === v || x[0].toLowerCase() === v.toLowerCase());
  if (b) return b[2];
  const m = v.match(/(\d+),(\d+),(\d+)/); if (m) return `rgb(${m[1]},${m[2]},${m[3]})`;
  return v.startsWith("#") ? v : "#FFFFFF";
}
function colorName(v: string) { if (!v || /^bylayer$/i.test(v)) return "ByLayer"; if (/^byblock$/i.test(v)) return "ByBlock"; return BASIC.find((x) => x[1] === v)?.[0] ?? v; }
function applyProp(app: App, key: string, sysvar: string, value: string) {
  if (app.selection.ids.length) return app.call("panel.set", { panel: "properties", key, value }).then(() => app.refresh(["drawing", "properties"]));
  return app.setVar(sysvar, value);
}
export function colorDropdown(app: App, width: number) {
  return field(width, "Color", (el) => {
    const v = app.sysvars.CECOLOR ?? "ByLayer";
    el.append(h("span", { class: "swatch", style: { background: colorHex(v, app) } }), h("span", { class: "t", text: colorName(v) }));
  }, () => [{ title: "ByLayer", action: () => applyProp(app, "color", "CECOLOR", "ByLayer") }, { title: "ByBlock", action: () => applyProp(app, "color", "CECOLOR", "ByBlock") }, { separator: true },
    ...BASIC.map(([n, aci, hex]) => ({ title: n, swatch: hex, action: () => applyProp(app, "color", "CECOLOR", aci) })), { separator: true },
    { title: "More Colors…", action: () => pickColor((hex) => applyProp(app, "color", "CECOLOR", hex)) }], app, ["sysvars", "layers", "selection"]);
}
function pickColor(done: (hex: string) => void) {
  const inp = h("input", { type: "color", style: { position: "fixed", left: "-100px" } }) as HTMLInputElement;
  document.body.append(inp);
  inp.addEventListener("change", () => { done(inp.value.toUpperCase()); inp.remove(); });
  inp.click();
}
export function linetypeDropdown(app: App, width: number) {
  return field(width, "Linetype", (el) => { el.append(icon("line.3.horizontal", 12), h("span", { class: "t", text: app.sysvars.CELTYPE ?? "ByLayer" })); },
    () => [{ title: "ByLayer", action: () => applyProp(app, "linetype", "CELTYPE", "ByLayer") }, { separator: true },
      ...["Continuous", "Dashed", "Hidden", "Center", "Phantom", "Dot", "DashDot", "Border", "Divide"].map((n) => ({ title: n, action: () => applyProp(app, "linetype", "CELTYPE", n) }))], app, ["sysvars", "selection"]);
}
export function lineweightDropdown(app: App, width: number) {
  const fmt = (v: string) => (!v || /^bylayer$/i.test(v) || Number(v) < 0 ? "ByLayer" : `${Number(v).toFixed(2)} mm`);
  return field(width, "Lineweight", (el) => { el.append(icon("lineweight", 12), h("span", { class: "t", text: fmt(app.sysvars.CELWEIGHT ?? "ByLayer") })); },
    () => [{ title: "ByLayer", action: () => applyProp(app, "lineweight", "CELWEIGHT", "ByLayer") }, { separator: true },
      ...LINEWEIGHTS.map((w) => ({ title: `${w.toFixed(2)} mm`, action: () => applyProp(app, "lineweight", "CELWEIGHT", String(w)) }))], app, ["sysvars", "selection"]);
}
export function dimstyleDropdown(app: App, width: number) {
  return field(width, "Dimension style", (el) => { el.append(h("span", { class: "t", text: app.sysvars.DIMSTYLE ?? "Standard" })); },
    () => ["Standard", "Architectural", "ISO-25"].map((n) => ({ title: n, checked: n === (app.sysvars.DIMSTYLE ?? "Standard"), action: () => app.setVar("DIMSTYLE", n) })), app, ["sysvars"]);
}
let visualStyle = "Realistic";
export function visualstyleDropdown(app: App, width: number) {
  return field(width, "Visual style of the 3D viewport", (el) => { el.append(icon("circle.lefthalf.filled", 12), h("span", { class: "t", text: visualStyle })); },
    () => [...VISUAL_STYLES.map((n) => ({ title: n, checked: n === visualStyle, action: () => { visualStyle = n; app.runCommand(`VSCURRENT ${n}`); app.emit("ui"); } })),
      ...(((window as any).archiVisualStyles?.custom ?? []) as { name: string }[]).map((c) => ({ title: c.name, checked: c.name === visualStyle, action: () => { visualStyle = c.name; app.runCommand(`VISUALSTYLES Current "${c.name}"`); app.emit("ui"); } }))], app, ["ui"]);
}
