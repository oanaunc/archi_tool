// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Script console content copied from the Mac app (ArchiApp/ScriptConsoleView.swift): examples, the archi API reference,
// built-in snippets and the completion lists.

export const EXAMPLES: { name: string; code: string }[] = [
  { name: "Draw a spiral", code: `// Archimedean spiral as one polyline (units: mm)
const pts = [];
for (let i = 0; i <= 720; i += 5) {
  const t = i * Math.PI / 180;
  const r = 200 + 40 * t;
  pts.push([r * Math.cos(t), r * Math.sin(t)]);
}
const id = archi.add({ type: "polyline", points: pts, layer: "0", color: "yellow" });
archi.print("Spiral", id, "with", pts.length, "vertices");
archi.run("ZOOM E");` },
  { name: "Grid of columns", code: `// Structural grid with columns at every intersection
const nx = 5, ny = 4, bay = 6000;
for (let i = 0; i < nx; i++)
  archi.addElement({ type: "grid", start: [i * bay, -1500], end: [i * bay, (ny - 1) * bay + 1500], label: String.fromCharCode(65 + i) });
for (let j = 0; j < ny; j++)
  archi.addElement({ type: "grid", start: [-1500, j * bay], end: [(nx - 1) * bay + 1500, j * bay], label: String(j + 1) });
let n = 0;
for (let i = 0; i < nx; i++)
  for (let j = 0; j < ny; j++) { archi.column(i * bay, j * bay, { size: 400, height: 3000 }); n++; }
archi.print(n, "columns placed");` },
  { name: "Parametric tower", code: `// Twisting tower: rotated floor slabs around a concrete core
const floors = 24, h = 3200, w = 24000, twist = 2.5; // degrees per floor
function square(size, angleDeg) {
  const a = angleDeg * Math.PI / 180, s = size / 2, pts = [];
  for (const [x, y] of [[-s, -s], [s, -s], [s, s], [-s, s]])
    pts.push([x * Math.cos(a) - y * Math.sin(a), x * Math.sin(a) + y * Math.cos(a)]);
  return pts;
}
for (let i = 0; i < floors; i++)
  archi.slab(square(w - i * 250, i * twist), { thickness: 300, topOffset: i * h, level: 0 });
archi.add({ type: "solid", kind: "box", origin: [-4000, -4000, 0], size: [8000, 8000, floors * h + 2000], layer: "A-ELEMENTS" });
archi.print("Tower with", floors, "floors, height", (floors * h / 1000).toFixed(1), "m");` },
  { name: "House walls", code: `// Simple house: four walls, a door, windows, a floor slab and a room
const W = 10000, D = 8000, t = 300;
const walls = [
  archi.wall(0, 0, W, 0, { thickness: t, height: 2800 }),
  archi.wall(W, 0, W, D, { thickness: t, height: 2800 }),
  archi.wall(W, D, 0, D, { thickness: t, height: 2800 }),
  archi.wall(0, D, 0, 0, { thickness: t, height: 2800 }),
];
archi.door(walls[0], 2000, { width: 1000, height: 2100 });
archi.window(walls[0], 6500, { width: 2400, height: 1400, sill: 800 });
archi.window(walls[1], 4000, { width: 1600 });
archi.window(walls[2], 5000, { width: 3000, height: 1600, sill: 600 });
archi.slab([[0, 0], [W, 0], [W, D], [0, D]], { thickness: 250, topOffset: 0 });
archi.room([[150, 150], [W - 150, 150], [W - 150, D - 150], [150, D - 150]], "Living");
archi.print("House created:", archi.elements().length, "elements");` },
  { name: "Inspect the document", code: `// Summaries and queries
const s = archi.summary();
archi.print("Project:", s.project.name, "·", s.entityCount, "entities,", s.elementCount, "elements");
for (const w of archi.elements({ type: "wall" }))
  archi.print("wall", w.id, "length", Math.hypot(w.geometry.end.x - w.geometry.start.x, w.geometry.end.y - w.geometry.start.y).toFixed(0));
archi.layers().map(l => l.name);` },
];

export const API: [string, string, string][] = [
  ["archi.run(line)", "Runs a command line exactly like typing it; returns the log lines.", "archi.run(\"CIRCLE 0,0 500\");"],
  ["archi.print(...values)", "Prints to the console and the command history.", "archi.print(\"Hello\");"],
  ["archi.add(entity)", "Adds a 2D/3D entity: {type:'line'|'circle'|'polyline'|'text'|'solid'…}. Returns its id.", "archi.add({ type: \"line\", a: [0, 0], b: [1000, 0] });"],
  ["archi.addElement(element)", "Adds a building element: wall, slab, column, grid, room…", "archi.addElement({ type: \"grid\", start: [0, -1000], end: [0, 9000], label: \"A\" });"],
  ["archi.wall(x1, y1, x2, y2, opts)", "Wall between two points (thickness, height, level). Returns the wall id.", "const w = archi.wall(0, 0, 6000, 0, { thickness: 200, height: 3000 });"],
  ["archi.door(wallId, offset, opts)", "Door hosted in a wall at an offset from its start.", "archi.door(w, 1500, { width: 900 });"],
  ["archi.window(wallId, offset, opts)", "Window hosted in a wall (width, height, sill).", "archi.window(w, 3500, { width: 1200, sill: 900 });"],
  ["archi.opening(wallId, offset, opts)", "Plain wall opening.", "archi.opening(w, 5000, { width: 1000, height: 2100 });"],
  ["archi.slab(points, opts)", "Floor slab from a boundary (thickness, topOffset, level).", "archi.slab([[0,0],[6000,0],[6000,4000],[0,4000]], { thickness: 250 });"],
  ["archi.room(points, name)", "Room / space with a name tag and area.", "archi.room([[0,0],[6000,0],[6000,4000],[0,4000]], \"Office\");"],
  ["archi.column(x, y, opts)", "Column at a point (size, height).", "archi.column(0, 0, { size: 400 });"],
  ["archi.entities(filter?)", "Lists entities; filter by {type, layer}.", "archi.entities({ type: \"circle\" }).length;"],
  ["archi.elements(filter?)", "Lists building elements; filter by {type, level}.", "archi.elements({ type: \"wall\" });"],
  ["archi.get(id)", "One entity or element as JSON.", "archi.get(1);"],
  ["archi.update(id, changes)", "Changes properties of an entity or element.", "archi.update(1, { layer: \"A-WALL\" });"],
  ["archi.remove(ids)", "Deletes entities/elements.", "archi.remove([1, 2]);"],
  ["archi.select(ids) / archi.selection()", "Sets or reads the selection.", "archi.select(archi.elements({ type: \"wall\" }).map(e => e.id));"],
  ["archi.layers() / archi.levels()", "Layers and levels of the document.", "archi.layers().map(l => l.name);"],
  ["archi.setVar(name, value) / getVar(name)", "System variables (saved in the drawing).", "archi.setVar(\"LTSCALE\", \"2\");"],
  ["archi.doc() / archi.summary()", "The whole document as JSON / a short summary.", "archi.summary();"],
  ["archi.undo() / archi.redo()", "Undo and redo.", "archi.undo();"],
  ["archi.commands()", "All command names with aliases and summaries.", "archi.commands().length;"],
  ["archi.evaluateGraph(graph) / archi.bakeGraph(graph)", "Evaluates a node graph object (Node Editor ▸ Graphs ▸ Export as Script) or bakes its output (one undo step).", "archi.bakeGraph(graph).length;"],
  ["archi.on(event, fn) / archi.off(event?)", "Event hooks: selectionChanged (ids), documentChanged ({changeCount}), elementAdded (ids), elementRemoved (ids), saved (path), commandEnded (name). Edits made inside a handler do not fire the hooks again.", "archi.on(\"elementAdded\", ids => archi.print(\"added\", ids.length));"],
  ["archi.panel({title, items})", "Script-defined panel: items {type:'number'|'field'|'toggle'|'text'|'button', name, label, value, min, max, call:'fnName' | command:'LINE'}. Buttons call the global function with the field values.", "function build(v) { archi.print(v.rise); }\narchi.panel({ title: \"Stairs\", items: [{ type: \"number\", name: \"rise\", label: \"Rise\", value: 175 }, { type: \"button\", label: \"Build\", call: \"build\" }] });"],
  ["archi.registerCommand(name, fn, options)", "Registers a command run by a named global function (options: aliases, summary, category, modifies); it is saved as a plugin and works from the command line, menus and agents.", "function hello() { archi.print(\"Hello\"); }\narchi.registerCommand(\"HELLO\", hello, { summary: \"Says hello\" });"],
  ["console.warn / console.error / console.assert / console.time / console.timeEnd / console.count / console.trace", "Debug output: warnings and errors are coloured; errors show the source line and the call stack.", "console.time(\"walls\"); /* … */ console.timeEnd(\"walls\");"],
];

export const SNIPPETS: [string, string][] = [
  ["Loop over selection", "for (const id of archi.selection()) {\n  const o = archi.get(id);\n  archi.print(id, o.type);\n}\n"],
  ["Walls of a rectangle", "const [w, h] = [8000, 6000];\nconst pts = [[0,0],[w,0],[w,h],[0,h]];\nfor (let i = 0; i < 4; i++) {\n  const a = pts[i], b = pts[(i + 1) % 4];\n  archi.wall(a[0], a[1], b[0], b[1], { thickness: 250, height: 3000 });\n}\n"],
  ["Grid of points", "for (let i = 0; i < 5; i++) {\n  for (let j = 0; j < 5; j++) {\n    archi.add({ type: \"point\", p: [i * 1000, j * 1000] });\n  }\n}\n"],
  ["Circle array", "const n = 12, r = 3000;\nfor (let i = 0; i < n; i++) {\n  const t = 2 * Math.PI * i / n;\n  archi.add({ type: \"circle\", center: [r * Math.cos(t), r * Math.sin(t)], radius: 200 });\n}\n"],
  ["Run commands", "archi.run(\"LAYER M A-NOTES \");\narchi.run(\"ZOOM E\");\n"],
  ["Count by type", "const counts = {};\nfor (const e of archi.entities()) counts[e.type] = (counts[e.type] || 0) + 1;\narchi.print(JSON.stringify(counts));\n"],
  ["Rename layers", "for (const l of archi.layers()) {\n  if (l.name.startsWith(\"OLD-\")) archi.run(`RENAME LA ${l.name} ${l.name.slice(4)} `);\n}\n"],
  ["Event hook", "archi.on(\"selectionChanged\", function (ids) {\n  archi.print(ids.length + \" selected\");\n});\n"],
  ["Script panel", "function offsetAll(v) {\n  archi.run(\"OFFSET \" + v.distance);\n}\narchi.panel({ title: \"Tools\", items: [\n  { type: \"number\", name: \"distance\", label: \"Distance\", value: 100, min: 1 },\n  { type: \"button\", label: \"Offset\", call: \"offsetAll\" },\n  { type: \"button\", label: \"Line\", command: \"LINE\" }\n] });\n"],
  ["Try / catch", "try {\n  \n} catch (e) {\n  archi.print(\"Error:\", e.message);\n}\n"],
];

export const API_MEMBERS: string[] = (() => {
  const names = new Set<string>();
  for (const [sig] of API) for (const part of sig.split(" / ")) {
    const t = part.trim();
    if (!t.startsWith("archi.") && t.includes(".")) continue;
    const n = (t.startsWith("archi.") ? t.slice(6) : t).split("(")[0];
    if (n) names.add(n);
  }
  for (const n of ["print", "run", "doc", "summary", "entities", "elements", "get", "add", "addElement", "update", "remove", "select", "selection",
    "setVar", "getVar", "layers", "levels", "wall", "door", "window", "opening", "slab", "room", "column", "undo", "redo", "commands"]) names.add(n);
  return [...names].sort();
})();
export const GLOBALS = ["archi", "console", "Math", "JSON", "Array", "Object", "Number", "String", "const", "let", "function", "return",
  "for", "while", "if", "else", "true", "false", "null", "undefined", "Math.PI", "Math.sin", "Math.cos", "Math.sqrt", "Math.round"];
