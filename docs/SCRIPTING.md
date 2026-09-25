# JavaScript scripting

Oanarina Archi Tool has a JavaScript console (JavaScriptCore). Open it from the **Script** ribbon tab
or the command line. Type a script, press **Run** (⌘↩) and read the output below the editor.
The **Examples** menu has ready-made scripts (spiral, grid of columns, parametric tower, house walls);
scripts can be opened from and saved to `.js` files.

Scripts run on a background thread; every `archi.*` call executes on the document's editor and each
mutating call is **one undo step**. Errors appear in red with their line number. JavaScript globals
persist between runs until you press the reset button.

Units are the document's units (millimetres by default). Angles in geometry JSON are **radians**;
helper options such as `rotation` for columns are in **degrees**.

## The `archi` object

| Call | Returns | Notes |
| --- | --- | --- |
| `archi.run(cmdLine)` | `string[]` log | Runs AutoCAD-style command line(s) to completion, e.g. `archi.run("LINE 0,0 1000,0 ")`. Unanswered prompts get Enter. Multiple lines separated by `\n` run in turn. |
| `archi.doc()` | object | The whole document in `.archi` JSON form. |
| `archi.summary()` | object | Counts by type, layers, levels, bounds, project info. |
| `archi.entities(filter?)` | `object[]` | Drafting entities. `filter`: `{type: "line", layer: "0"}`. |
| `archi.elements(filter?)` | `object[]` | BIM elements. `filter`: `{type: "wall", level: 0}`. |
| `archi.get(id)` | object \| null | One entity or element. |
| `archi.add(obj \| obj[])` | id \| ids | Adds entities (see *Geometry JSON*). |
| `archi.addElement(obj \| obj[])` | id \| ids | Adds BIM elements. |
| `archi.update(id, patch)` | object | Patches an entity/element (see *Patches*). |
| `archi.remove(ids)` | count | Deletes entities/elements (doors/windows go with their wall). |
| `archi.select(ids)` / `archi.selection()` | ids | Sets / reads the selection. |
| `archi.setVar(name, value)` / `archi.getVar(name)` | string | AutoCAD-style system variables. |
| `archi.layers()` / `archi.levels()` | `object[]` | Layer and level tables. |
| `archi.commands()` | `object[]` | Command names, aliases, categories, summaries. |
| `archi.undo()` / `archi.redo()` | | |
| `archi.print(...)`, `console.log(...)` | | Writes to the console output (objects are shown as JSON). |

### Building helpers

| Call | Default options |
| --- | --- |
| `archi.wall(x1, y1, x2, y2, opts?)` | `thickness`, `height` (from the drafting settings), `baseOffset: 0`, `justification: "center" \| "left" \| "right"`, `wallType`, `bulge`, `level`, `layer`, `material`, `name` |
| `archi.door(wallId, offset, opts?)` | `width: 900`, `height: 2100`, `style: "single" \| "double" \| "sliding" \| …`, `flipHand`, `flipFacing` |
| `archi.window(wallId, offset, opts?)` | `width: 1200`, `height: 1200`, `sill: 900`, `style: "casement" \| "fixed" \| …` |
| `archi.opening(wallId, offset, opts?)` | empty opening, `width: 900`, `height: 2100` |
| `archi.slab(points, opts?)` | `thickness: 200`, `topOffset: 0`, `holes: [[…]]`, `level` |
| `archi.room(points, name?, opts?)` | `number`, `height: 2700` |
| `archi.column(x, y, opts?)` | `size` or `width`/`depth: 300`, `height: 3000`, `rotation` (degrees), `round` |

`offset` is the distance along the wall from its start point to the opening's centre; the opening must fit
inside the wall. Points are `[x, y]` arrays or `{x, y}` objects. Each helper returns the new element id.

## Geometry JSON

Entities use the same Codable format as `.archi` files, with a `"type"` and the geometry fields at the top
level (or under `"geometry"`). Missing fields get defaults, and any point may be written as `[x, y]`.
Optional entity properties: `layer`, `color` (`"ByLayer"`, ACI number, `"#RRGGBB"`, `"red"`…), `linetype`,
`lineweight` (mm), `props` (string map).

```js
archi.add({ type: "line", a: { x: 0, y: 0 }, b: { x: 1000, y: 0 } });
archi.add({ type: "circle", center: [500, 500], radius: 250, color: "red" });
archi.add({ type: "arc", center: [0, 0], radius: 1000, start: 0, end: Math.PI / 2 });
archi.add({ type: "polyline", points: [[0, 0], [2000, 0], [2000, 1000]], closed: true });
archi.add({ type: "polyline", vertices: [[0, 0, 0.4142], [1000, 0]] });        // [x, y, bulge]
archi.add({ type: "text", position: [0, -500], height: 250, content: "Hello" });
archi.add({ type: "hatch", loops: [[[0, 0], [1000, 0], [1000, 1000], [0, 1000]]], pattern: "ANSI31", scale: 10 });
archi.add({ type: "dimension", kind: "linear", points: [[0, 0], [1000, 0], [500, -400]] });
archi.add({ type: "solid", kind: "box", origin: [0, 0, 0], size: [1000, 1000, 3000] });
```

Element types: `wall`, `slab`, `column`, `beam`, `door`, `window`, `opening`, `roof`, `stair`, `railing`,
`space` (alias `room`), `curtainWall`, `component`, `grid`. Optional: `level`, `layer`, `material`, `name`, `props`.

```js
const w = archi.addElement({ type: "wall", start: [0, 0], end: [6000, 0], thickness: 250, height: 3000 });
archi.addElement({ type: "window", hostWall: w, offset: 3000, width: 1800, sill: 900 });
archi.addElement({ type: "roof", boundary: [[0, 0], [6000, 0], [6000, 4000], [0, 4000]], kind: "gable", pitch: 35, level: 0 });
archi.addElement({ type: "stair", start: [500, 500], direction: 0, width: 1000, totalRise: 3000, riserCount: 17 });
```

## Patches

`archi.update(id, patch)` changes properties of an entity (`layer`, `color`, `linetype`, `lineweight`, `props`)
or an element (`level`, `name`, `layer`, `material`, `props`). Any other key is a geometry field:

```js
archi.update(12, { radius: 400, color: "#F5C518" });      // circle
archi.update(w, { height: 3500, thickness: 300 });          // wall
archi.update(w, { geometry: { end: [8000, 0] } });          // same as { end: [8000, 0] }
```

## Examples

```js
// Offset copies of every line on layer "0"
for (const e of archi.entities({ type: "line", layer: "0" }))
  archi.add({ type: "line", a: [e.geometry.a.x, e.geometry.a.y + 500], b: [e.geometry.b.x, e.geometry.b.y + 500] });

// Commands work too — the same command line as the app
archi.run("CIRCLE 0,0 500");
archi.run("ZOOM E");

// Rename every room by area
for (const r of archi.elements({ type: "space" })) archi.update(r.id, { name: "Room " + r.id });
```

The same API is available to local agents through `eval_js` (see [AGENT-API.md](AGENT-API.md)).
