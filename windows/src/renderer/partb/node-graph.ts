// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Node graph editing in the shell (the Mac NodeGraph editing API: add, remove, connect with type and cycle checks,
// groups, comments, sub-graphs for packages). The graph is the same JSON the engine evaluates (ArchiCore NodeGraph) and
// stores in the drawing (NODEGRAPH variables), so graphs move between the Mac and Windows unchanged.

export type PortType = "number" | "point" | "geometry" | "element";
export interface Port { name: string; type: PortType; def: number }
export interface Kind { kind: string; title: string; category: string; output: PortType; inputs: Port[] }
export interface GNode { id: number; kind: string; x: number; y: number; params: Record<string, number> }
export interface GLink { from: number; to: number; port: string }
export interface GFrame { id: number; title: string; x: number; y: number; width: number; height: number; color: number }
export interface GComment { id: number; text: string; x: number; y: number; width: number }
export interface Graph { nodes: GNode[]; links: GLink[]; nextID: number; groups: GFrame[]; comments: GComment[] }

const P = (name: string, type: PortType, def: number): Port => ({ name, type, def });
export const KINDS: Kind[] = [
  { kind: "number", title: "Number", category: "Numbers", output: "number", inputs: [] },
  { kind: "range", title: "Range", category: "Numbers", output: "number", inputs: [P("start", "number", 0), P("stop", "number", 10000), P("count", "number", 5)] },
  { kind: "series", title: "Series", category: "Numbers", output: "number", inputs: [P("start", "number", 0), P("step", "number", 1000), P("count", "number", 5)] },
  { kind: "point", title: "Point", category: "Geometry", output: "point", inputs: [P("x", "number", 0), P("y", "number", 0), P("z", "number", 0)] },
  { kind: "line", title: "Line", category: "Geometry", output: "geometry", inputs: [P("start", "point", 0), P("end", "point", 1000)] },
  { kind: "circle", title: "Circle", category: "Geometry", output: "geometry", inputs: [P("center", "point", 0), P("radius", "number", 500)] },
  { kind: "rectangle", title: "Rectangle", category: "Geometry", output: "geometry", inputs: [P("center", "point", 0), P("width", "number", 2000), P("height", "number", 1000)] },
  { kind: "polygon", title: "Polygon", category: "Geometry", output: "geometry", inputs: [P("center", "point", 0), P("radius", "number", 1000), P("sides", "number", 6)] },
  { kind: "polyline", title: "Polyline", category: "Geometry", output: "geometry", inputs: [P("points", "point", 0), P("closed", "number", 0)] },
  { kind: "extrude", title: "Extrude", category: "Solids", output: "geometry", inputs: [P("profile", "geometry", 0), P("height", "number", 3000), P("base z", "number", 0)] },
  { kind: "move", title: "Move", category: "Transform", output: "geometry", inputs: [P("geometry", "geometry", 0), P("dx", "number", 0), P("dy", "number", 0)] },
  { kind: "rotate", title: "Rotate", category: "Transform", output: "geometry", inputs: [P("geometry", "geometry", 0), P("angle°", "number", 45), P("center", "point", 0)] },
  { kind: "array", title: "Array", category: "Transform", output: "geometry", inputs: [P("geometry", "geometry", 0), P("columns", "number", 3), P("rows", "number", 2), P("dx", "number", 3000), P("dy", "number", 3000)] },
  { kind: "polarArray", title: "Polar Array", category: "Transform", output: "geometry", inputs: [P("geometry", "geometry", 0), P("count", "number", 6), P("center", "point", 0), P("angle°", "number", 360)] },
  { kind: "merge", title: "Merge", category: "Transform", output: "geometry", inputs: [P("a", "geometry", 0), P("b", "geometry", 0), P("c", "geometry", 0)] },
  { kind: "random", title: "Random", category: "Numbers", output: "number", inputs: [P("count", "number", 5), P("min", "number", 0), P("max", "number", 1000), P("seed", "number", 1)] },
  { kind: "loft", title: "Loft", category: "Solids", output: "geometry", inputs: [P("bottom", "geometry", 0), P("top", "geometry", 0), P("height", "number", 3000), P("base z", "number", 0)] },
  { kind: "boolean", title: "Boolean", category: "Solids", output: "geometry", inputs: [P("a", "geometry", 0), P("b", "geometry", 0), P("op 0∪ 1− 2∩", "number", 1)] },
  { kind: "wall", title: "Wall", category: "Building", output: "element", inputs: [P("path", "geometry", 0), P("thickness", "number", 200), P("height", "number", 3000)] },
  { kind: "slab", title: "Slab", category: "Building", output: "element", inputs: [P("boundary", "geometry", 0), P("thickness", "number", 200), P("top offset", "number", 0)] },
  { kind: "roof", title: "Roof", category: "Building", output: "element", inputs: [P("boundary", "geometry", 0), P("pitch°", "number", 30), P("kind 0flat 1shed 2gable 3hip", "number", 2), P("eave height", "number", 3000)] },
];
export const CATEGORIES = ["Numbers", "Geometry", "Solids", "Transform", "Building"];
export const kindOf = (k: string) => KINDS.find((x) => x.kind === k) ?? KINDS[0];

export const LAYOUT = { width: 188, header: 24, row: 26 };
export function nodeHeight(k: string) { return LAYOUT.header + LAYOUT.row * kindOf(k).inputs.length + (k === "number" ? 52 : 0) + 22; }
export function inputPort(n: GNode, i: number) { return { x: n.x, y: n.y + LAYOUT.header + LAYOUT.row * i + LAYOUT.row / 2 }; }
export function outputPort(n: GNode) { return { x: n.x + LAYOUT.width, y: n.y + LAYOUT.header / 2 }; }
export const param = (n: GNode, k: string, d: number) => (n.params && n.params[k] !== undefined ? n.params[k] : d);

export function empty(): Graph { return { nodes: [], links: [], nextID: 1, groups: [], comments: [] }; }
export function normalize(g: any): Graph {
  const nodes = (g?.nodes ?? []).map((n: any) => ({ id: n.id, kind: n.kind, x: n.x ?? 0, y: n.y ?? 0, params: n.params ?? {} }));
  return { nodes, links: g?.links ?? [], nextID: g?.nextID ?? (Math.max(0, ...nodes.map((n: GNode) => n.id)) + 1), groups: (g?.groups ?? []).map((f: any) => ({ color: 0, ...f })), comments: (g?.comments ?? []).map((c: any) => ({ width: 200, ...c })) };
}
export const clone = (g: Graph): Graph => JSON.parse(JSON.stringify(g));

export function add(g: Graph, kind: string, x: number, y: number): number {
  const n: GNode = { id: g.nextID, kind, x, y, params: kind === "number" ? { value: 1000, min: 0, max: 10000 } : {} };
  g.nodes.push(n); g.nextID += 1;
  return n.id;
}
export function remove(g: Graph, id: number) {
  g.nodes = g.nodes.filter((n) => n.id !== id);
  g.comments = g.comments.filter((c) => c.id !== id);
  g.groups = g.groups.filter((f) => f.id !== id);
  g.links = g.links.filter((l) => l.from !== id && l.to !== id);
}
export const node = (g: Graph, id: number) => g.nodes.find((n) => n.id === id);
export function depends(g: Graph, a: number, b: number): boolean {
  const stack = [a], seen = new Set<number>();
  while (stack.length) {
    const n = stack.pop()!;
    if (n === b) return true;
    if (seen.has(n)) continue;
    seen.add(n);
    for (const l of g.links) if (l.to === n) stack.push(l.from);
  }
  return false;
}
/** Connects an output to an input (replacing the input's link). Refuses type mismatches and cycles. */
export function connect(g: Graph, from: number, to: number, port: string): boolean {
  const a = node(g, from), b = node(g, to);
  if (from === to || !a || !b) return false;
  const p = kindOf(b.kind).inputs.find((x) => x.name === port);
  if (!p || kindOf(a.kind).output !== p.type) return false;
  if (depends(g, from, to)) return false;
  g.links = g.links.filter((l) => !(l.to === to && l.port === port));
  g.links.push({ from, to, port });
  return true;
}
export function disconnect(g: Graph, to: number, port: string) { g.links = g.links.filter((l) => !(l.to === to && l.port === port)); }
export function outputNodes(g: Graph): number[] {
  const used = new Set(g.links.map((l) => l.from));
  return g.nodes.filter((n) => (kindOf(n.kind).output === "geometry" || kindOf(n.kind).output === "element") && !used.has(n.id)).map((n) => n.id);
}

// ---- groups and comments ----
export function frameContains(f: GFrame, n: GNode) { const cx = n.x + LAYOUT.width / 2, cy = n.y + 20; return cx >= f.x && cx <= f.x + f.width && cy >= f.y && cy <= f.y + f.height; }
export function members(g: Graph, f: GFrame) { return g.nodes.filter((n) => frameContains(f, n)).map((n) => n.id); }
export function addGroup(g: Graph, title: string, ids: number[] = [], x = 40, y = 40): number {
  const ns = g.nodes.filter((n) => ids.includes(n.id));
  let f: GFrame = { id: g.nextID, title, x, y, width: 360, height: 220, color: 0 };
  if (ns.length) {
    const x0 = Math.min(...ns.map((n) => n.x)), y0 = Math.min(...ns.map((n) => n.y));
    const x1 = Math.max(...ns.map((n) => n.x + LAYOUT.width)), y1 = Math.max(...ns.map((n) => n.y + nodeHeight(n.kind)));
    f = { id: g.nextID, title, x: Math.max(0, x0 - 20), y: Math.max(0, y0 - 36), width: x1 - x0 + 40, height: y1 - y0 + 56, color: 0 };
  }
  g.groups.push(f); g.nextID += 1;
  return f.id;
}
export function moveGroup(g: Graph, id: number, dx: number, dy: number) {
  const f = g.groups.find((x) => x.id === id);
  if (!f) return;
  const inside = new Set(members(g, f));
  f.x += dx; f.y += dy;
  for (const n of g.nodes) if (inside.has(n.id)) { n.x += dx; n.y += dy; }
}
export function addComment(g: Graph, text: string, x: number, y: number): number { g.comments.push({ id: g.nextID, text, x, y, width: 200 }); g.nextID += 1; return g.nextID - 1; }
export function parameterName(g: Graph, n: GNode) {
  const f = g.groups.find((x) => frameContains(x, n));
  return ((f && f.title ? f.title : "number") + "_" + n.id).replace(/[^A-Za-z0-9_]/g, "_");
}

// ---- packages (NodePackages.swift) ----
export interface Snippet { name: string; description: string; graph: Graph }
export interface Package { format: string; name: string; version: string; author: string; description: string; snippets: Snippet[] }
export const PACKAGE_FORMAT = "oanarina-archi-nodes";
export const PACKAGE_EXT = "archinodes";
export function subgraph(g: Graph, ids: Set<number>): Graph {
  const sel = g.nodes.filter((n) => ids.has(n.id));
  const x0 = sel.length ? Math.min(...sel.map((n) => n.x)) : 0, y0 = sel.length ? Math.min(...sel.map((n) => n.y)) : 0;
  return { nodes: sel.map((n) => ({ ...n, params: { ...n.params }, x: n.x - x0, y: n.y - y0 })), links: g.links.filter((l) => ids.has(l.from) && ids.has(l.to)), nextID: Math.max(0, ...sel.map((n) => n.id)) + 1, groups: [], comments: [] };
}
export function insert(g: Graph, other: Graph, x: number, y: number): Map<number, number> {
  const map = new Map<number, number>();
  for (const n of [...other.nodes].sort((a, b) => a.id - b.id)) { map.set(n.id, g.nextID); g.nodes.push({ ...n, params: { ...n.params }, id: g.nextID, x: n.x + x, y: n.y + y }); g.nextID += 1; }
  for (const l of other.links) { const f = map.get(l.from), t = map.get(l.to); if (f !== undefined && t !== undefined) g.links.push({ from: f, to: t, port: l.port }); }
  return map;
}
export function makePackage(g: Graph, name: string, author = "", description = ""): Package {
  let snippets: Snippet[] = g.groups.map((f) => { const ids = new Set(members(g, f)); return ids.size ? { name: f.title, description: "", graph: subgraph(g, ids) } : null; }).filter(Boolean) as Snippet[];
  if (!snippets.length && g.nodes.length) snippets = [{ name, description: "", graph: subgraph(g, new Set(g.nodes.map((n) => n.id))) }];
  return { format: PACKAGE_FORMAT, name, version: "1.0", author, description, snippets };
}
export function decodePackage(text: string): Package {
  const p = JSON.parse(text);
  if ((p.format ?? PACKAGE_FORMAT) !== PACKAGE_FORMAT) throw new Error("Not an Oanarina node package.");
  if (!String(p.name ?? "").trim()) throw new Error("The package has no name.");
  return { format: PACKAGE_FORMAT, name: p.name, version: p.version ?? "1.0", author: p.author ?? "", description: p.description ?? "", snippets: (p.snippets ?? []).map((s: any) => ({ name: s.name, description: s.description ?? "", graph: normalize(s.graph ?? {}) })) };
}
export function encodePackage(p: Package) { return JSON.stringify(p, null, 2); }
