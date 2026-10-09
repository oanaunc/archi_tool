# Agent API

AI agents and other programs can drive Oanarina Archi Tool in two ways:

1. **Local agent server** in the running app — JSON-RPC 2.0 over HTTP on `127.0.0.1`, acting on the open document
   (the user sees every change live and can undo it).
2. **`archi-cli --mcp`** — a headless [Model Context Protocol](https://modelcontextprotocol.io) server over stdio that edits
   `.archi` files without the app (for Claude Desktop, Claude Code and other MCP clients).

Both use the same JSON formats for entities and elements as the JavaScript API (see [SCRIPTING.md](SCRIPTING.md)).
Units are the document units (millimetres by default); geometry angles are radians.

## 1. Local agent server (HTTP JSON-RPC)

Turn it on in **Settings → Agents** (off by default). It listens on `127.0.0.1:47800` only (never on the network) and every
`/rpc` request needs `Authorization: Bearer <token>`. The token is random for each launch; it is shown in Settings and
written, together with the port, to

```
~/Library/Application Support/Oanarina Archi Tool/agent.json      (mode 0600)
{ "port": 47800, "token": "…", "url": "http://127.0.0.1:47800/rpc", "pid": 1234, "started": "…" }
```

The file is removed when the server stops. Requests with a non-loopback `Host` header are rejected (DNS-rebinding
protection), and no CORS headers are sent, so web pages cannot call the server.

### Endpoints

| Request | Auth | Response |
| --- | --- | --- |
| `GET /health` | no | `{"status":"ok","app":"Oanarina Archi Tool","rpc":"/rpc"}` |
| `POST /rpc` | Bearer token | JSON-RPC 2.0 response (batches supported; notifications get `204`) |

### Methods

| Method | Params | Result |
| --- | --- | --- |
| `run_command` | `{command}` — one or more command lines | `{log: string[]}` |
| `get_document` | – | the document as `.archi` JSON |
| `get_document_summary` | – | counts, layers, levels, bounds, project info |
| `list_entities` | `{type?, layer?, limit?}` | `Entity[]` |
| `list_elements` | `{type?, level?}` | `BIMElement[]` |
| `add_entity` | `{entity}` object or array | `{ids}` |
| `add_element` | `{element}` object or array | `{ids}` |
| `update_entity` (alias `update`, `update_element`) | `{id, patch}` | the updated object |
| `delete` (alias `delete_entities`) | `{ids}` | `{deleted}` |
| `select` | `{ids}` | `{selection}` |
| `get_selection` | – | `{selection}` |
| `export` | `{format: pdf\|dxf\|svg\|obj\|stl\|glb\|ifc\|csv\|archi, path, layout?, level?, kind?}` | `{path}` |
| `screenshot` | `{width?=1600, height?=1200, level?, paper?=false}` | `{mimeType:"image/png", width, height, image: base64}` — the 2D plan, selection highlighted |
| `list_commands` | – | `[{name, aliases, category, summary}]` |
| `eval_js` | `{code}` | `{output: string[], value, error}` — runs JavaScript with the `archi` API |
| `undo`, `redo`, `list_methods` | – | |

`export` paths must be absolute (`~` is expanded). `pdf` with `layout` plots that sheet at true scale on its paper size;
without it the current level is plotted to fit A3. `csv` exports schedules (`kind`: walls, doors, windows, rooms, slabs, all).
Every mutating call is a single undo step in the app.

Errors use JSON-RPC codes: `-32700` parse error, `-32600` invalid request, `-32601` unknown method,
`-32602` invalid params, `-32000` operation failed (message explains), `-32001` no document open.

### Example (shell)

```sh
INFO=~/Library/Application\ Support/Oanarina\ Archi\ Tool/agent.json
TOKEN=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['token'])" "$INFO")
curl -s http://127.0.0.1:47800/rpc -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"add_element","params":{"element":{"type":"wall","start":[0,0],"end":[5000,0]}}}'
curl -s http://127.0.0.1:47800/rpc -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc":"2.0","id":2,"method":"run_command","params":{"command":"CIRCLE 2500,2000 500"}}'
```

### Example (Python)

```python
import json, os, urllib.request
info = json.load(open(os.path.expanduser("~/Library/Application Support/Oanarina Archi Tool/agent.json")))
def rpc(method, **params):
    req = urllib.request.Request(info["url"], json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(),
                                 {"Authorization": "Bearer " + info["token"], "Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req))
    if "error" in r: raise RuntimeError(r["error"]["message"])
    return r["result"]

print(rpc("get_document_summary"))
wall = rpc("add_element", element={"type": "wall", "start": [0, 0], "end": [6000, 0]})["ids"][0]
rpc("add_element", element={"type": "door", "hostWall": wall, "offset": 1500})
open("plan.png", "wb").write(__import__("base64").b64decode(rpc("screenshot")["image"]))
```

## 2. MCP server: `archi-cli --mcp`

`archi-cli` ships inside the app bundle (`Oanarina Archi Tool.app/Contents/MacOS/archi-cli`). With `--mcp` it speaks MCP
(protocol version `2025-06-18`, newline-delimited JSON-RPC over stdin/stdout) and edits the `.archi` file given as argument.
If the file does not exist yet, a new document is started and created on the first `save`. **Changes are written only
when the agent calls `save`.** DXF files can be opened too (save then writes `.archi` to the path you give).

Tools:

| Tool | Arguments | Purpose |
| --- | --- | --- |
| `run_command` | `command`, `maxLines?` | AutoCAD-style command line(s); returns the log (last `maxLines`, default 500, with `truncated`/`totalLines` when cut). Streams every log line while running (see below) |
| `get_document_summary` | – | overview: units, layers, levels, counts, bounds, unsaved changes |
| `get_document` | – | whole document JSON |
| `list_entities` | `type?`, `layer?`, `limit?` | drafting entities |
| `list_elements` | `type?`, `level?` | BIM elements |
| `add_entity` | `entity` | add entities (object or array) |
| `add_element` | `element` | add BIM elements |
| `update_entity` | `id`, `patch` | modify an entity/element |
| `delete` | `ids` | delete |
| `save` | `path?` | save as `.archi` (default: the opened file) |
| `export` | `path`, `format?`, `level?` | dxf, dxf12, svg, ifc, ifczip, obj, stl, glb, 3mf, usda, usdz, step, ply, plt (HP-GL/2), xlsx, csv, geojson, points, analytical, opensees (Tcl), gbxml, cobie, dae, fbx, igs (IGES), dgn (V7), laser (CNC/laser SVG), html (read-only viewer), archit (git-friendly text), 3dm (Rhino, version 4 archive), dwg (converter needed), archi |
| `list_commands` | `category?` | available commands |
| `undo` | – | undo last change |
| `import_file` | `path`, `format?`, `offset?` | merge .archi, .archit, .dxf, .dwg (converter), .ifc/.ifczip, .svg, .obj, .stl, .3mf, .gltf/.glb, .fbx, .usd/.usda/.usdz, .igs/.iges, .dgn (V7), .pdf (vectors and text), .dwfx, .ply, .off, .amf, .dae, .step, .geojson, .cityjson, .shp, .osm, .asc, .xlsx, CSV points, XYZ/PTS or LAS point clouds, .3dm (Rhino 2–8), .skp (SketchUp, converter needed) into the document |
| `takeoff` | `level?`, `format?` (json, csv) | quantity takeoff of walls, slabs, roofs, columns, beams, openings and spaces |
| `cost_estimate` | `prices?`, `path?`, `format?` | cost of the takeoff from unit rates (inline, a JSON file, or the drawing's UNITPRICE rates) |
| `room_schedule` | `level?`, `format?` | rooms with net/gross area, perimeter, height and volume |
| `clash` | `tolerance?`, `ids?`, `includeSpaces?` | hard clashes between elements and 3D solids |
| `check_model` | – | model audit (walls, openings, rooms, duplicates, levels) |
| `sun_position` | `datetime`, `latitude?`, `longitude?` | sun azimuth/altitude, sunrise and sunset |
| `sun_path` | `date`, `utcOffset?`, `latitude?`, `longitude?` | hourly sun azimuth/altitude between sunrise and sunset |
| `heat_loss` | `indoor?`, `outdoor?`, `airChanges?`, `degreeDays?`, `thermalBridge?`, `format?` | envelope U·A·ΔT + ventilation design heat loss, per component and element, annual heating demand |
| `u_values` | `ids?` | U-value (EN ISO 6946) and layers of walls, slabs, roofs, openings; `exterior` flag for walls |
| `daylight` | `level?`, `format?` | average daylight factor and window-to-floor ratio per room |
| `code_check` | `rules?` (object), `path?` | building-code rules (room area/height/width, window ratio, stairs, ramps, doors); issues with ids and zoom boxes |
| `level_areas` | `format?` | gross and net floor area per level |
| `schedule` | `kind` (walls, doors, windows, rooms, slabs, all), `format?` | element schedule rows |
| `structural_model` | `solve?`, `deadLoad?`, `liveLoad?` | analytical model (nodes, members, panels, supports, loads); `solve` adds displacements and reactions |
| `energy_extras` | `level?` | room reverberation times (RT60) and embodied carbon by material |
| `plan_svg` | `level?`, `width?`, `background?`, `path?` | render-free SVG image of a level's plan (text; also written to `path`) |
| `ifc_validate` | `path?`, `schema?` (IFC2X3/IFC4/IFC4X3_ADD2), `modelView?` | IFC checks of a file or the model's export: syntax, schema, references, GlobalIds, attribute kinds, EXPRESS WHERE rules (`WR-<Entity>.<Rule>`), units, containment; issues on the model's own export list the `elements` to zoom to |
| `ids_check` | `idsPath`, `ifcPath?` | Information Delivery Specification check of the model's IFC export or an IFC file |
| `egress` | `level?`, `maxDistance?`, `format?` | longest walking distance from each room to the nearest exit (doors in exterior walls or `exit=1`, stairs above the ground level) on a 250 mm grid around walls and columns; route from the farthest point; limit `EGRESSMAX` (m, default 45) |
| `accessibility` | `level?`, `minDoorWidth?`, `turningDiameter?` | door clear widths (default 850 mm, `A11YDOORWIDTH`) and the largest free turning circle in bathrooms (default Ø1500 mm, `A11YTURNING`) clear of fixtures |
| `energy_balance` | `hdd?`, `heatingDays?`, `format?` | seasonal heating need (EN ISO 13790): losses from degree days (latitude table or `HDD`), solar gains per window orientation, internal gains, utilisation factor |
| `bill_of_quantities` | `prices?`, `path?`, `currency?`, `vat?`, `contingency?`, `format?` | priced bill of quantities by trade (numbered items, subtotals, contingency, VAT) |
| `takeoff_by_phase` | `format?` | quantities per construction phase (new / demolished) and level |
| `compare` | `path`, `overlayPath?`, `format?` | differences between an older file and the open document (added/removed/modified by id and geometry); optional colour-coded overlay `.archi` |
| `markups` | `status?` (open, resolved, all) | review markups with author, date, status, replies, linked elements and view |
| `validate_exchange` | `format` (gbxml, cobie), `path?` | schema requirements check of the gbXML / COBie export or a file |
| `markup_add` | `comment`, `title?`, `min?`, `max?`, `elements?`, `author?` | adds a markup (cloud around `min`–`max` or around the elements); undoable |
| `markup_update` | `id`, `status?`, `reply?`, `author?`, `delete?` | resolve/reopen, reply to or delete a markup (id or its list number); undoable |
| `bcf_import` | `path` | imports BCF 2.x topics (.bcfzip) as markups (camera, selection by IFC GlobalId, comments); undoable |
| `run_batch` | `path?` or `jobs?`, `stopOnError?` | runs batch jobs on separate documents (see Batch jobs); the open document is not changed |

`export` also writes `kml`/`kmz` (Google Earth, placed at the project latitude/longitude and north angle; KMZ includes the
COLLADA model), `bcf` (markups as BCF 2.1), `boq` (bill of quantities from the drawing's COST: rates, `.csv` or `.xlsx`) and
`svglayers` (plan with one Inkscape/Illustrator layer per drawing layer; `svg` output of archi-cli is layered too).

### Resources and prompts

The server also offers MCP **resources** (`resources/list`, `resources/templates/list`, `resources/read`):

| URI | Type | Content |
| --- | --- | --- |
| `archi://document/summary` | application/json | project info, units, counts, bounds, markups |
| `archi://document` | application/json | the whole document (.archi JSON) |
| `archi://takeoff`, `archi://takeoff/phases` | text/csv | quantity takeoff; by phase and level |
| `archi://schedules/{kind}` | text/csv | walls, doors, windows, rooms, slabs, all |
| `archi://markups`, `archi://levels`, `archi://layers` | application/json | review markups, levels, layers |
| `archi://element/{id}` | application/json | one BIM element or entity |
| `archi://plan/{level}` | image/svg+xml | plan of a level with layers as groups |

and **prompt templates** (`prompts/list`, `prompts/get`): `review_model` (`focus?`), `quantity_report` (`currency?`, `vat?`),
`energy_advice` (`target?` kWh/m²a), `draw_room` (`name`, `width`, `depth`, `origin?`) and `resolve_markups`. Each returns
a user message with instructions and the current model context (summary, model-checker findings, takeoff, energy balance
or open markups).

### Markups and BCF

Markups are stored in the document on layer `MARKUP`: a revision cloud (props `markup` = id, `author`, `date` ISO 8601,
`status` open/resolved, `title`, `comment`, `elements` = linked ids, `view` = centre x,y and height, `camera` = eye, target,
fov, ortho, `level`, `reply1…` = author␟date␟text) and a note text (`markupNote` = id). Commands: `MARKUP`
(Add/List/Resolve/Reopen/Reply/Zoom/Delete), `BCFOUT`, `BCFIN`; author = `USERNAME` variable, else the project author.
BCF 2.1: one topic per markup (`markup.bcf` with comments; `viewpoint.bcfv` with an orthogonal top view for plan markups or a
perspective camera in metres, and the linked elements as `Component IfcGuid` — the GlobalIds the IFC exporter writes).

### Batch jobs

`archi-cli --batch jobs.json`, the `run_batch` tool or the `BATCH` command in the app run jobs, each on its own document;
relative paths are resolved against the jobs file's folder:

```json
{"stopOnError": false, "jobs": [
  {"name": "plan", "input": "house.archi", "import": ["survey.dxf"], "commands": ["LAYER M A-NEW ", "WALL 0,0 5000,0 "],
   "script": "finish.scr", "outputs": ["house.dxf", {"path": "house.ifc", "format": "ifc"}, {"path": "l1.svg", "level": 1}],
   "reports": [{"tool": "takeoff", "path": "quantities.csv"}, {"tool": "egress", "path": "egress.json", "arguments": {"level": 0}}],
   "save": "house-out.archi"}]}
```

`reports` accept `takeoff`, `check_model`, `room_schedule` and every read-only analysis tool above (with `arguments`); a
`.csv` path asks for CSV. The CLI prints one line per job and a JSON summary (`jobs[{name, ok, error?, written[],
commandErrors, logTail}]`, `failed`, `succeeded`) and exits with status 1 when a job failed.

### Streaming long command logs

`run_command` can take a long time (scripts, imports). Two ways to follow it live:

- Send `_meta.progressToken` with the `tools/call` request: every log line is sent as
  `{"method":"notifications/progress","params":{"progressToken":…,"progress":n,"message":"<line>"}}` before the result.
- Or enable logging once with `logging/setLevel` (`"level":"info"`): log lines arrive as
  `{"method":"notifications/message","params":{"level":"info","logger":"archi","data":"<line>"}}`.

The final result still carries the log (capped by `maxLines`).

### Analysis examples

```json
{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"heat_loss","arguments":{"indoor":20,"outdoor":-12,"airChanges":0.6}}}
{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"code_check","arguments":{"rules":{"minRoomArea":7,"stair":{"maxRiser":180,"minTread":270}}}}}
{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"plan_svg","arguments":{"level":0,"width":1600,"path":"~/Desktop/plan.svg"}}}
```

Code rules (`code_check`, command `CODECHECK`/`CODERULES`) are JSON; keys that are absent switch that rule off:
`name`, `minRoomArea` (m²), `minCeilingHeight` (mm), `minWindowToFloor` (ratio), `noWindowRooms` (name substrings),
`rooms` (`[{match, minArea, minWidth, minHeight, minWindowToFloor}]`), `stair` (`{maxRiser, minRiser, minTread, maxTread,
stepFormulaMin, stepFormulaMax, minWidth, maxRisersPerFlight}` in mm), `maxRampGradient` (rise/run), `minDoorWidth` (clear, mm).

Thermal data: conductivities default to typical EN ISO 10456 values by material name; override with drawing variables
`LAMBDA:<material>` (W/m·K) or `UVALUE:<wall type|wall|roof|floor|window|door|curtainWall>` (W/m²·K), or an element's
`uValue` prop. Walls are exterior when `isExternal=1`, their type name says exterior, rooms lie on one side only, or (no rooms)
they lie on the outline of the level.

The analytical model JSON (`structural_model`, `export` format `analytical`, command `ANALYTICALMODEL`) uses format
`archi-analytical-1`: metres, kN, MPa; `nodes[{id, xyz, support[6]}]`, `members[{id, element, type, nodes[2], material,
section{shape, b, h, A, Iy, Iz, J}}]`, `panels[{id, element, type, outline, thickness, material, areaLoad_kN_m2}]`,
`loads{nodal[{node, F, M}], memberUniform[{member, w}]}`, `materials[{name, E_MPa, G_MPa, unitWeight_kN_m3}]`.

### DWG files

DWG is read and written through a converter installed on the Mac — the free ODA File Converter (in /Applications) or
LibreDWG (`brew install libredwg`) — or the path stored with the `DWGCONVERTER` command / `ARCHI_DWG_CONVERTER`
environment variable. Without one, `import_file`/`export` of `.dwg` return guidance to save DXF from the original CAD program.

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{"mcpServers":{"archi":{"command":"/Applications/Oanarina Archi Tool.app/Contents/MacOS/archi-cli","args":["--mcp","~/Documents/project.archi"]}}}
```

(`~` in the file argument is expanded by archi-cli.) Restart Claude Desktop; the tools appear under “archi”.

### Claude Code

```sh
claude mcp add archi -- "/Applications/Oanarina Archi Tool.app/Contents/MacOS/archi-cli" --mcp ~/Documents/project.archi
```

### Other CLI modes

```sh
archi-cli project.archi                          # REPL: type commands, :save, :export plan.svg, :quit
archi-cli project.archi --script build.scr --out project.archi
archi-cli drawing.dxf --out drawing.archi        # convert
echo "WALL 0,0 5000,0 " | archi-cli --out model.ifc
archi-cli model.archi --out model.step                # also .ifczip .gltf/.glb .ply .plt .xlsx .dae … (see `export` formats)
```

Script files contain one command line per line; lines starting with `;` are comments. `archi-cli --batch jobs.json` runs
batch jobs (see above).

```sh
archi-cli model.archi --js tools.js --script run.scr --out model.archi   # JavaScript first (may register commands), then the script
archi-cli model.archi --py build.py arg1 arg2                          # Python 3 with the archi module; the drawing is saved at the end
archi-cli --python-module ~/lib/python                                 # writes archi.py
archi-cli --watch ~/Inbox --rules rules.json [--once]                  # automation triggers (section 8)
```

Batch conversion (one line per file; exit status 1 when any file failed):

```sh
archi-cli --convert dxf plans/*.archi --outdir out/        # also ifc, ifczip, step, glb, obj, stl, 3mf, svg, xlsx, gbxml, cobie, dae, archi …
archi-cli --convert archi survey/*.dxf site.ifc            # inputs may be any importable format
```

## 3. Plugins (JavaScript SDK)

A plugin is a folder with a `plugin.json` manifest and a JavaScript entry file. Plugin folders are read from
`~/Library/Application Support/Oanarina Archi Tool/Plugins/` (one sub-folder per plugin), from the folder set with
`PLUGINS Folder` (drawing variable `PLUGINFOLDER`), and with archi-cli from `--plugins DIR`.

```json
{
  "id": "com.example.roomtools",
  "name": "Room Tools",
  "version": "1.0",
  "description": "Tags and checks for rooms.",
  "author": "Ana",
  "main": "main.js",
  "permissions": ["document"],
  "commands": [
    {"name": "ROOMBOX", "aliases": ["RBX"], "summary": "Draws a 4 × 3 m room outline.", "function": "roomBox", "category": "Plugins", "modifies": true}
  ]
}
```

```js
// main.js — every command calls a global function
function roomBox() {
  const id = archi.add({type: "polyline", vertices: [[0,0],[4000,0],[4000,3000],[0,3000]], closed: true, layer: "A-AREA"});
  archi.print("Room outline #" + id);
}
```

- Command names are letters, digits, `_` or `-`. A plugin cannot replace a built-in command (it is skipped and reported);
  aliases already in use are dropped. Plugin commands work on the command line, in scripts and through the agent API, and
  each run is one undo step.
- `PLUGINS` manages plugins: `List`, `Reload` (rescan and register), `Enable` / `Disable` (saved in
  `plugins-state.json` of the plugin folder; a disabled plugin's commands refuse to run), `Info`, `New` (creates a plugin
  skeleton, optionally replaying a `.scr` script or the running `SCRIPTRECORD` recording), `Folder`.
- `SCRIPT2JS` converts a command script (`.scr`) or the current recording into JavaScript with one `archi.run(...)` per command.

**Commands from scripts (`archi.registerCommand`).** A script or plugin file can define commands at load time:

```js
function grid() {
  const n = Number(archi.getVar("GRIDN") || 3);
  for (let i = 0; i < n; i++) archi.add({type: "line", a: [i * 1000, 0], b: [i * 1000, 5000], layer: "S-GRID"});
}
archi.registerCommand("JSGRID", grid, {aliases: ["JG"], summary: "Grid lines", category: "Scripts", modifies: true});
if (archi.mode === "load") archi.print("tools loaded");   // top-level code also runs when a command runs; guard it
```

`archi.registerCommand(name, fn | "fnName", options?)` registers a command backed by a *named global* function of the same
file (run with `archi-cli --js file.js`, or evaluated by the app's script engine through the core hook below). Rules: names
are letters/digits/`_`/`-`; built-in commands and other scripts' commands cannot be replaced (the call is reported and
ignored); registering again from the same file updates the command. Each run re-evaluates the file (`archi.mode` is
`"load"` at registration, `"command"` when the command runs), calls the function, and is one undo step; lines queued with
`archi.run` run after the command, each its own undo step (scripts, the REPL and MCP wait for them).

Core API for hosts: `PluginRegistry.registerScriptCommand(_ command: PluginCommand, source: String, sourceURL: URL, into:
CommandRegistry) throws -> String` (plugin id `script.<file name>`, kept across `reload()`), `unregisterScriptCommands(script:
name:registry:)`, `LoadedPlugin.init(manifest:directory:source:enabled:)`, `PluginRegistry.scriptPlugins`. The evaluator
hook `PluginRegistry.evaluator` is called with the script's pseudo-plugin and the function name, exactly as for manifest
plugins; a host collects `registerCommand` calls made during a top-level evaluation and passes them to
`registerScriptCommand` (see `app/Sources/archi-cli/PluginRunner.swift`, `CLIPlugins.run(_:function:_:)`).

The `archi` object available to plugin functions (archi-cli; the app's script engine provides the same calls):

| Call | Result |
| --- | --- |
| `archi.print(text)` / `console.log(text)` | writes to the command history |
| `archi.doc()` | summary: project, units, layers, levels, counts, bounds |
| `archi.entities([type[, layer]])`, `archi.elements([type[, level]])` | objects as JSON (`.archi` format) |
| `archi.selection()` | ids of the selected objects |
| `archi.add(entity)` → id, `archi.addElement(element)` → id | adds a drawing object / building element (same JSON as `add_entity` / `add_element`) |
| `archi.update(id, patch)`, `archi.remove([ids])` | edits / deletes objects |
| `archi.getVar(name)`, `archi.setVar(name, value)` | drawing variables |
| `archi.run("COMMAND inputs ")` | queued: runs after the plugin command finishes (each line its own undo step) |
| `archi.pluginName` | the plugin's name |

Core API for hosts (Swift, `ArchiCore`): `PluginRegistry.shared` (`folders`, `reload()`, `plugins`, `problems`,
`setEnabled(_:_:)`, `register(into:)`, `commandDefinitions()`, `scaffold(in:name:command:script:registry:)`),
`PluginManifest`, `PluginCommand`, `LoadedPlugin`, and the hook `PluginRegistry.evaluator:
@MainActor (LoadedPlugin, String, Editor) async throws -> Void`, which the host sets to evaluate `plugin.source` and call
the named function (archi-cli: `app/Sources/archi-cli/PluginRunner.swift`). `ScriptConverter` turns script lines into
JavaScript.

## 4. Document history, recovery and collaboration

| Command | What it does |
| --- | --- |
| `VERSIONS Save/List/Restore/Diff/Delete/Prune` | named checkpoints in `<drawing>.archi-versions/` (vNNNN.archi + versions.json); Restore is undoable; Diff compares two versions or a version and the current drawing (`0`) |
| `RECOVER <file>` | opens a damaged `.archi`: truncated JSON is closed after the last complete object, undecodable objects/settings are dropped, the model is audited (orphan doors/windows, duplicate ids, missing layers) |
| `JOURNAL On/Off/Now/Status` | change journal (`.archijournal`, JSON lines: base snapshot + deltas) written every n seconds to `~/Library/Application Support/Oanarina Archi Tool/Recovery/`; a half-written last line is ignored on replay |
| `RECOVERYFILES` | lists change journals and app autosave copies; `Open n` replays / repairs one into the editor |
| `MODELMERGE <base> <theirs>` | three-way merge into the current drawing (ours); conflicts keep ours, are listed and selected |
| `STANDARDS Export/Import/Check <file.archistd>` | office standards package: layers, linetypes, text/dim styles, materials, wall/floor/opening types, view templates, hatch patterns |
| `ISSUETRACKER Add/List/Show/Status/Assign/Priority/Comment/Zoom/Delete/Csv` | issues stored in the drawing (variable `ISSUES`, JSON) with elements, saved view and comments |
| `IFCOPTIONS` | IFC export schema (`IFC4` / `IFC4X3` → `IFC4X3_ADD2`), MVD (`ReferenceView` / `DesignTransferView`), base quantities |

Saving `.archi` through archi-cli / batch jobs keeps the previous file as `<name>.bak` (drawing variable `ISAVEBAK=0` turns
it off). `.archiz` is the compressed package: the drawing plus its images, textures and external references (opened with
paths made absolute). Swift: `DocumentVersions`, `ArchiFile.recover(_:)`, `ArchiFile.save(_:to:backup:)`,
`DocumentJournal`, `AutosaveJournal`, `RecoveryFiles`, `ThreeWayMerge.merge(base:ours:theirs:)`, `StandardsPackage`,
`IssueTracker`, `ArchiPackage`.

## 5. Building checks

| Command | Method |
| --- | --- |
| `LOADTAKEDOWN` | slabs split into tributary cells carried by the nearest column or bearing wall; dead = slab self weight + `LOADSDL` (1.5 kN/m²) + column self weight; imposed by room usage (EN 1991-1-1: residential 2.0, office 3.0, assembly/retail 5.0, storage 7.5; roofs `LOADROOF` 0.75; room prop `liveLoad`); stacked columns accumulate; ULS 1.35G + 1.5Q, SLS, axial stress |
| `RAINWATER` | roof plan area incl. overhang; runoff C (pitched 1.0, flat 0.8, green 0.3, prop `runoff`); Q = C·i·A with `RAININTENSITY` (0.03 l/s·m²); downpipes from EN 12056-3 capacities (DN100 = 4.6 l/s); eave gutter length; harvest = A·rain·C·0.8 |
| `PARKINGCHECK` | required spaces from `PARKINGRULES` (`office=35;apartment=unit:1;…`, area per space or spaces per room) vs. placed parking components; accessible spaces 1 per 25 (then 1 per 50 above 100) |
| `FIRECOMPARTMENTS` | room areas per `fireCompartment` prop (else per level) vs. `FIREMAXAREA` (2500 m², ×2 with `FIRESPRINKLERS=1`); walls between compartments below `FIRERATINGREQ` minutes (prop `fireRating`, `Pset_WallCommon.FireRating`) are selected |
| `TLEN`, `ANGLEBETWEEN`, `DISTTOOBJECT`, `POINTINSIDE` | total length, angle between lines, shortest point–object distance, point-in-contour test |

## 6. Exchange details

- DXF: sheet layouts are written as paper space (`*Paper_Space`, `*Paper_SpaceN` blocks, `LAYOUT` objects with paper size,
  `VIEWPORT` entities with view centre and scale; view kind, level, title and title block as Archi XDATA) and read back;
  block attribute definitions are written as `ATTDEF` and inserts' `ATTRIB`s sit at their definitions; hatch patterns
  carry their line families and unknown patterns read from a file are stored as `HPPAT:<NAME>`; `MLINE` and `ACAD_TABLE`
  are read (element polylines, table cells).
- IFC export: props named `<Set>.<Property>` go to that property set (typed: booleans, numbers, `ThermalTransmittance`),
  others to `Archi_Properties`; `Qto_*BaseQuantities` for walls, slabs, columns, beams, spaces, doors and windows; wall /
  door / window types as `IfcWallType` / `IfcDoorType` / `IfcWindowType` with `IfcRelDefinesByType`. IFC import maps type
  objects back to wall types and opening types and reads quantities in the file's area/volume units (props in m, m², m³).
- OBJ import reads the `mtllib` materials (Kd, d/Tr, Ns, Pr/Pm, `map_Kd` with `-s` tiling); USD import reads USDA and
  USDZ (meshes, transforms, UsdPreviewSurface colours and textures). glTF/GLB export embeds PNG/JPEG textures with UVs.
- USD import applies full xformOp stacks in `xformOpOrder` (translate, rotateX/Y/Z/XYZ…, orient, scale, transform, `!invert!`),
  `metersPerUnit`, `upAxis` and `primvars:displayColor`. FBX: binary 7.4 export (meshes, materials, mm, Z up) and binary
  (7.x, compressed arrays, 7.5 64-bit headers) / ASCII import with model transforms, units, up axis and material colours.
  IGES 5.3: lines, arcs/circles, polylines (106), B-splines (126), points; units from the global section.
- IFC import reads `IfcMapConversion` + `IfcProjectedCRS` back into the project latitude/longitude, elevation, north angle and
  `GEOCRS`.

## 7. Python bridge

`archi.py` (standard library only) drives `archi-cli --mcp` over stdio and mirrors the JavaScript API:

```python
import archi
doc = archi.open("house.archi")                      # or module functions on $ARCHI_FILE (set by archi-cli --py)
doc.run("WALL 0,0 5000,0 ")                          # log lines
w = doc.add_element({"type": "wall", "start": [0, 0], "end": [0, 4000]})[0]
doc.add_element({"type": "door", "hostWall": w, "offset": 1500})
ids = doc.add([{"type": "circle", "center": [0, 0], "radius": 250}])
doc.update(ids[0], {"radius": 400}); doc.remove(ids)
print(doc.entities(type="line"), doc.elements(type="wall"), doc.summary())
doc.call("takeoff", format="csv")                      # any MCP tool
doc.save(); doc.close()
```

Functions: `open(path, cli)`, `run`, `summary`, `doc`, `entities(type, layer, limit)`, `elements(type, level)`, `add`,
`add_element`, `update`, `remove`, `save(path)`, `export(path, format, level)`, `undo`, `commands(category)`, `get_var`,
`set_var`, `call(tool, **args)`; errors raise `archi.ArchiError`. The executable comes from `$ARCHI_CLI`, the `PATH` or the app
bundle. `archi-cli file.archi --py script.py [args]` puts the module on `PYTHONPATH`, sets `ARCHI_FILE` and saves the drawing
when the script ends; `archi-cli --python-module DIR` writes `archi.py`.

## 8. Automation triggers

`archi-cli --watch DIR --rules rules.json [--once]` (Swift: `AutomationWatcher(folder:rulesData:)`, `pending()`,
`runOnce(host:progress:)`) runs a batch job for every new or changed file in `DIR` matching a rule, then POSTs the job summary
(`{file, rule, ok, written[], error?}`) as JSON to the rule's `webhook`:

```json
{"interval": 5, "rules": [{"name": "dxf to archi", "pattern": "*.dxf",
  "job": {"input": "{file}", "commands": ["AUDIT"], "outputs": ["out/{name}.archi", "out/{name}.ifc"],
          "reports": [{"tool": "check_model", "path": "out/{name}-check.json"}]},
  "webhook": "https://example.org/hooks/archi"}]}
```

Placeholders: `{file}`, `{name}`, `{ext}`, `{dir}`; jobs use the batch-job format (section 2). Processed files are remembered
in `DIR/.archi-automation.json`; `--once` handles the pending files and exits (status 1 when a job failed).

## 9. More commands and formats (this release)

| Command | What it does |
| --- | --- |
| `GITVERSION Commit/Log/Diff/Checkout` | git versioning of the drawing as `<name>.archit` (one line per layer, block, material, level, object and element; `ArchiText.encode/decode/diff`, `GitVersioning`); Diff lists every added/removed/modified object; Checkout is undoable |
| `CENTRAL Permissions Show/Role/Layer/Default/Check` | signed access policy of a central model (`<central>.permissions.json` + `.sig`, Ed25519 key from `SIGNKEY`; the first publication pins the key as `POLICYKEY` in central): viewer / editor / admin roles and protected layers, enforced on `CENTRAL Sync`; a hand-edited or foreign-signed policy locks the model read-only; refused local objects are saved to `<local>.rejected-<time>.archi` (`Permissions`, `AccessPolicy`) |
| `CENTRAL Create/Local/Sync/Borrow/Relinquish/Owners` | work sharing: central `.archi` + local copies (`CENTRALFILE`), element borrowing (`<central>.owners.json`), synchronise under a lock: edits to objects owned by others are rejected, concurrent edits keep central, new ids are renumbered (`CentralModel`) |
| `TRACEREVIEW New/Enter/Exit/Show/Hide/Zoom/List/Close/Import/Delete` | trace overlays (`TRACE-<name>` layers, non-plotting) with author, view window and linked elements (variable `TRACES`) |
| `SHAREVIEW` | self-contained read-only HTML viewer (all level plans, pan/zoom, element info, rooms, layers); export format `html` |
| `PDFIMPORT`, `PDFMARKUPS` | PDF page vectors/text (optional content → layers, ToUnicode text, form XObjects, object streams) at a scale; PDF comments → markups linked to the elements under them (`PDFFile`, `PDFImport`) |
| `DWFIMPORT` | DWFx (XPS) sheets: paths, colours, line weights, glyph text |
| `DGNIMPORT`, `DGNEXPORT` | MicroStation V7 design files: lines, line strings, shapes, curves, circles/ellipses, arcs, text; levels ↔ layers (V8 files are not supported) |
| `LASEREXPORT` | CNC/laser SVG in mm: joined paths, red cut / blue engrave, kerf compensation (`LASERSCALE`, `LASERKERF`) |
| `IFCOPTIONS` | adds `IFC2X3` (Coordination View 2.0; IFC4 stream converted: attributes, door/window styles, flow terminals, style assignments) and georeferencing (`IfcMapConversion` + `IfcProjectedCRS` from the project location, `GEOCRS`, `IFCGEOREF`); Reference View writes `IfcTriangulatedFaceSet`, DTV/2x3 faceted B-reps |
| `IFCMAP Set/List/Remove/Clear` | IFC class mapping per component category / element type (`IFCMAP:<key>`); element prop `IfcExportAs` (`IfcSanitaryTerminal.WASHHANDBASIN`) wins |
| `STRUCTLOAD Point/Line/Area`, `STRUCTSUPPORT` | loads (kN, kN/m, kN/m²; case) and supports (Fixed/Pinned/Roller/6-digit code) on layer `S-LOADS`, attached to the analytical model; `ANALYTICALMODEL` writes `.tcl` for OpenSees (export format `opensees`) |
| `THERMALBRIDGES` | linear thermal bridges (corners, floor edges, balconies, eaves, reveals, columns) with ψ (`PSI:<kind>`) and H_TB |
| `WORKSCHEDULE Generate/List/Duration/Link/Simulate/Resources/Level/Gantt/Csv` | 4D: tasks by level and trade from quantities, CPM on a working-day calendar, element states at a date, resources (histogram, over-allocation, cost, levelling), Gantt SVG; exported to IFC as `IfcWorkSchedule`/`IfcTask`/`IfcRelSequence` |
| `ENERGYPLUS Export/Run` | EnergyPlus 9.4 IDF from rooms (zones, outward-ordered surfaces, windows, layered constructions, ideal loads); Run uses an installed EnergyPlus + EPW |
| `AUTODIMPLAN`, `AUTONAMEROOMS`, `QAASSIST`, `PLANGEN`, `ASK` | plan dimension chains; room names/numbers from fixtures and shape; model-checker explanations and fixes; plan options from a room programme; natural-language requests — all ask before bulk edits and are one undo step |
| `POINTCLOUDVIEW Clip/Density/Reset`, `PCPLANE`, `SCANTOBIM` | section-box clipping and octree LOD of point clouds (`PointOctree`), snap + local plane fit, RANSAC planes → walls/slabs; LAS 1.0–1.4 import (`LASReader`) |
| `LISPLOAD`, `LISP` | AutoLISP subset (`LispInterpreter`): `defun c:NAME` becomes a command; `(command …)`, `entget/entmod/ssget`, list/string/math functions |

Plotting: `PLOTROLL` (roll width mm) and `PLOTMARGIN` make HP-GL/2 output (`plt`) size the page (`PS`) and rotate to fit the
roll. Performance: `SpatialIndex` (STR R-tree: window/point queries, k-nearest) for culling and picking; current-format
`.archi` files decode in one pass.

## 10. File life cycle, collaboration and analysis (round 6)

### Command-line options

| Option | What it does |
| --- | --- |
| `--template FILE` | new untitled drawing from a template (`.architemplate` or `.archi`; everything kept except the project name) — combine with `--script`/`--out` |
| `--upgrade FILES…` | upgrades older `.archi`/`.architemplate` files to the current format; originals kept as `<name>.v<N>.archi.bak` |
| `--verify FILE` | save/reopen round-trip check (exit 1 and the changed sections when not lossless) |
| `--metadata FILE` | Spotlight metadata as JSON (`kMDItemTitle`, authors, layers as keywords, text content, levels, rooms) |
| `--api-reference [FILE]` | generated Markdown reference: every command, every MCP tool with its parameters, file formats, sample scripts |
| `--run-samples` | runs the reference's sample scripts (exit 1 if one fails) |
| `--license` | licence (GPL-3.0-or-later) and privacy notice |
| `--check-update APPCAST [--current V]` | newest compatible version in a Sparkle appcast (`UpdateCheck`; the only network access, on request); downloads can be checked with `UpdateCheck.verify` against `SHA256SUMS.txt` |

### MCP tools added

| Tool | Result |
| --- | --- |
| `daylight_annual` `{epwPath?, gridSpacing?, format?}` | per room sDA300/50% and ASE1000,250h (IES LM-83), mean autonomy, pass/fail |
| `generative_design` `{program, adjacent?, facing?, area?, seed?, generations?, limit?}` | Pareto-optimal layouts (rooms with rectangles, objective values); build one with `GENDESIGN` |
| `wind_case` `{path, speed?, direction?, roughness?}` | writes an OpenFOAM case folder |
| `file_check` | `{lossless, changedSections, formatVersion}` |

### Commands

| Command | What it does |
| --- | --- |
| `SAVECOPY` | Save a Copy in any format (the open drawing keeps its name and dirty state) |
| `SAVECHECK` | verifies that saving and reopening gives an identical document |
| `UPGRADEFILE` | upgrades a file or every `.archi` in a folder (`ArchiFile.upgradeFile`, `ArchiFile.inspect`) |
| `TEMPLATEOUT`, `TEMPLATEIN` | write a `.architemplate` (name, description) / start a new drawing from one (undoable); `ArchiTemplate` |
| `FILEMETADATA` | Spotlight attributes of the drawing or a file (`SpotlightMetadata`) |
| `PDFATTACH`, `PDFUNDERLAYS List/Reload/Detach/Fade` | PDF page underlays by reference: faded locked layer `PDF-UNDERLAY`, object snaps on the page geometry, reload after the PDF changed (`PDFUnderlay`) |
| `DROPIMPORT` | files imported as if dropped: images/PDFs attached, exchange formats merged side by side (`ExternalContent.drop`); `ExternalContent.insert(data, type:)` handles pasted SVG, PDF, DXF, `.archi`, images and text |
| `BREPOUT`, `BREPIN` | OpenCASCADE BREP (FreeCAD `.brep/.brp`): export as shells of planar faces; import with locations, stored triangulations, line/circle/ellipse edges |
| `E57OUT`, `E57IN` | ASTM E57 point clouds (paged container with CRC-32C, CompressedVector bit-pack: Float/ScaledInteger/Integer, spherical or Cartesian, colour, intensity, scan poses) |
| `COEDIT Join/Sync/Status/Leave` | co-editing through a shared folder (iCloud Drive, network share): every object is a last-writer-wins register with a Lamport stamp, ops in `<site>.ops.jsonl`, ids from a per-user range; replicas converge, concurrent edits of one object are reported (`CoEditSession`) |
| `BCFSERVER Connect/Projects/Pull/Push` | BCF API 2.1/3.0 (OpenCDE) client with bearer token: topics, comments, viewpoints and selections ↔ markups (`BCFAPIClient`) |
| `RESOLVECONFLICTS` | merges sync-conflict copies (`House 2.archi`, `(conflicted copy)`, OneDrive `-HOST`) three-way; copies moved to `<name>.archi-conflicts/` (`ConflictCopies`) |
| `DAYLIGHTANNUAL` | climate-based daylight from an EPW (or clear-sky year): sDA/ASE per room, optional coloured work-plane grid (`ClimateDaylight`, `HourlyClimate`) |
| `CFDEXPORT`, `WINDRESULTS` | OpenFOAM wind case (ABL inlet, snappyHexMesh, pedestrian-level sample); results as arrows with Lawson comfort classes (`WindStudy`) |
| `GENDESIGN` | generative layout design (seeded GA: daylight, proportions, adjacencies, orientation, compactness), builds the chosen design after confirmation |
| `SKETCHTOWALLS` | scanned/photographed plan (PNG, BMP, PGM/PPM) → walls (Otsu threshold, stroke bands, corner snapping), after confirmation (`SketchToModel`, `RasterImage`) |
| `CLASHMANAGE Run/List/Group/Status/Assign/Zoom/Csv` | clash results kept between runs with status (new/active/reviewed/approved/resolved), assignee, groups (type/level/proximity) and zoom links (`ClashManager`) |
| `TIME Display/ON/OFF/Reset` | creation/update dates, editing time without idle gaps (`EditTime.touch`), user timer (`TDINDWG`, `TDUSRTIMER`) |

Text: DXF writes characters outside the Basic Multilingual Plane as `\U+D83D\U+DE00` surrogate pairs (read back as one
character, also in layer names); SVG marks right-to-left paragraphs with `direction="rtl"` (`TextDirection`).

## 11. Exchange, validation, analysis and sharing (round 10)

### Command-line options

| Option | What it does |
| --- | --- |
| `--docs DIR [--source DOCSDIR]` | writes the documentation as an offline HTML site with search (user guide, scripting, agent API, architecture, roadmap, command reference); sources default to the app bundle's resources or `./docs` (`DocSite`, `Markdown`) |
| `--verify-download FILE --ed-signature SIG --public-key KEY` | Sparkle EdDSA (Ed25519) check of a downloaded update; `UpdateCheck.check(download:item:publicKey:)` also checks the appcast length and falls back to `SHA256SUMS.txt` |
| `--convert FMT FILES…` | new formats: `dxf2004` … `dxf2018` (written as `.dxf`), `ifcxml`, `saf` (Structural Analysis Format `.xlsx`), `ifcstructural` (IFC4 structural analysis view) |

### Commands

| Command | What it does |
| --- | --- |
| `DXFOUTVERSION` | DXF of a chosen version: R12, R2000, R2004 (AC1018), R2007 (AC1021, UTF-8 text), R2010, R2013, R2018 (AC1032) (`DXFWriter.write(_:version:)`, `DXFVersion`) |
| `IFCXMLOUT` | ifcXML (IFC4, ISO 10303-28): every instance an element with `id`, simple attributes as XML attributes, references as `ref`/`xsi:nil`, typed values as `…-wrapper`; `.zip`/`.ifczip` names write an IfcZIP holding the ifcXML. `.ifcXML` (and ifcXML inside IfcZIP) imports through `IMPORTFILE` (`IFCXML.fromSTEP` / `IFCXML.toSTEP`) |
| `IFCVALIDATE` | now checks every instance against the full IFC2X3 / IFC4 / IFC4X3 ADD2 schema tables (unknown/abstract classes, attribute counts, `*` for derived attributes, required attributes, value kinds), normative rules (spatial decomposition, unused resources, closed shells) and the standard `Pset_`/`Qto_` templates (names, properties, measure types, enumeration values, applicability); issues of the model's own export list and zoom to the drawing's elements (`IFCValidator.elements(for:in:doc:)`, `IFCSchemaTable`, `IFCPsetTable`) |
| `ANALYTICALMODEL` | also writes `.xlsx` (SAF 2.x sheets: materials, cross-sections, point connections, curve and surface members, supports, load groups/cases, surface and point actions) and `.ifc` (IfcStructuralAnalysisModel with point connections, boundary conditions, curve/surface members, material profiles, load groups and actions, SI units) (`StructuralExchange`) |
| `LAZCONVERTER` | shows/sets the LAZ decompressor (laszip, pdal or las2las); `.laz` then imports like `.las` (`LAZConverter`) |
| `PRESENTOUT` | sheets and saved views as a self-contained HTML slide show: vector SVG slides, arrow keys/click, F full screen, N speaker notes (sheet title-block field `notes`) (`Presentation`) |
| `DOCSITE` | the documentation site from inside the app |
| `SIGNKEY`, `SIGNFILE`, `VERIFYSIGNATURE`, `TRUSTSIGNER` | Ed25519 signing key (kept in Application Support), detached `<file>.sig` signatures of any file (signer, time, SHA-256, signature), verification (valid / modified / invalid, trusted via the drawing's `TRUSTEDSIGNERS`) (`Ed25519`, `SHA512`, `FileSignature`) |
| `COLORBLINDCHECK` | layer colours checked for protanopia, deuteranopia and tritanopia (Machado 2009 simulation, CIEDE2000) and against the background; Fix re-colours conflicting layers from the Okabe–Ito palette, undoable (`ColourAccessibility`) |
| `SHADOWDIAGRAM` | ground shadows for a date and times (`9:00,12:00,15:00` or `8-18/1`) at the project location: hatches on `A-SHADOW-hhmm` layers with areas, and/or an SVG image sequence with an animated HTML page (`ShadowStudy`) |
| `ENERGYPLUS Run` | also reads the results: completion and errors (`eplusout.err`), site energy, EUI, end uses, unmet hours (`eplustbl.csv`), per-zone heating/cooling energy and peaks (`eplusout.csv`), written to the rooms as `energyHeating_kWh`, `energyCooling_kWh`, `peakHeating_kW`…; walls, floors and ceilings between rooms are exported as interzone surface pairs (`EnergyPlusExport.results`, `applyResults`) |
| `SURVEYLINES` | survey field-to-finish: coded points (`EP1 B` … `EP1 E`, `C` closes) joined into polylines with their elevations, points moved to feature layers from the description keys (`SURVEYCODES`: `EP=V-ROAD-EDGE:line; TREE=V-TREE:point`) (`SurveyCodes`) |
| `DAYLIGHTRADIANCE Export/Import` | Radiance study for climate-based daylight: scene and materials (glass transmissivity from the glazing transmittance), the rooms' work-plane sensors, sky receiver and `run.sh` (epw2wea, gendaymtx, rfluxmtx, dctimestep, rmtxop); Import reads `total.ill`/`direct.ill` and reports sDA300/50% and ASE1000,250h per room (`RadianceDaylight`) |
| `MEMORYREPORT` | memory estimate of the drawing by kind (drafting, elements, meshes, point clouds, blocks, sheets, images), the app's footprint and the budget (`MEMORYBUDGET` MB, default ¼ of the Mac's memory) with advice; point-cloud imports are limited to what fits (`POINTLIMIT`) (`MemoryBudget`) |


IFC 4.3: plan polylines on a layer whose name contains `ALIGNMENT` (or with prop `alignment = 1`) export as `IfcAlignment`
(horizontal LINE / CIRCULARARC segments from the polyline and its bulges, a constant-gradient vertical layout from the
prop `elevations`, an `Axis` curve), aggregated into the project with the site; importing reads `IfcAlignment` layouts
(lines, arcs, clothoids and other transitions, vertical gradients) back onto layer `IFC-ALIGNMENT` (`AlignmentGeometry`).

Core APIs for the viewers: `ParallelMesh.build(doc:)` (same result as `MeshBuilder.build`, built concurrently),
`BackgroundRegenerator` (off-main-thread rebuilds, only the newest document state delivered) and `MeshLOD`
(coarser levels per mesh group and the level to draw from the projected size; sub-pixel objects skipped).

STEP import (`STEPIN`, `IMPORTFILE`) now reads curved B-reps — planes, cylinders, cones, spheres, tori, B-spline/Bézier/rational
surfaces, extrusion and revolution surfaces with line, circle, ellipse, B-spline and composite edges — as well as AP242
tessellated geometry and assembly placements (mapped items, transformed representation relationships), with colours
(`StepBRepReader`, `STEPImporter.assemble`).

## 12. Built-in solvers, validation and large clouds (round 11)

| Command / option | What it does |
| --- | --- |
| `WINDRESULTS Solve` | built-in pedestrian-level wind screening without an external CFD package: a 2D lattice Boltzmann solver (D2Q9, BGK + Smagorinsky, half-way bounce-back) on the plan section of the building mass above 1.5 m (openings are closed by the wall above them, enclosed interiors filled), log-law inflow from `WINDSPEED`/`WINDDIRECTION`/`WINDROUGHNESS`, zero-gradient outlet, free-slip sides, time-averaged over one flow-through after two flow-throughs of warm-up; draws the same speed-coloured arrows and Lawson comfort classes as imported OpenFOAM samples. Prompts: speed at 10 m, direction (from, clockwise from north), cell size in m (0 = automatic), arrow spacing. Verified against the analytic Poiseuille profile (`WindFlow.solve`, `WindFlow.study`, `WindFlow.poiseuille`). A 2D section ignores down-wash from tall buildings: use `CFDEXPORT` (OpenFOAM) for design decisions |
| `THERMALBRIDGES` + `PSIMETHOD=ISO10211` | ψ of wall corners (convex and re-entrant), intermediate floor edges and balconies computed with a 2D EN ISO 10211 heat-conduction model from the walls' layer build-ups (plies, outside first) and the slab material/thickness instead of the EN ISO 14683 defaults; `PSI:<kind>` overrides still win. The finite-volume solver (`HeatConduction2D.solve`, rectilinear grid, surface resistances Rsi 0.13 / Rse 0.04, adiabatic cut-off planes ≥ 1 m, preconditioned conjugate gradients) reproduces the analytic Annex C rectangle within 0.1 K and gives ψ = 0 for plain walls; `JunctionPsi.corner`, `JunctionPsi.floorEdge`, `JunctionPsi.plainWall` return L2D, U, ψe, ψi and the temperature factor fRsi |
| `SUNPOSITION Validate` | compares the solar calculator with published results — the NREL SPA worked example (Reda & Andreas 2004: zenith, azimuth, equation of time, sunrise, sunset) and Meeus examples 25.a/28.a (declination, equation of time) — and prints PASS/FAIL per quantity with the deviation and tolerance (`SolarCalculator.validate`, `SolarCalculator.references`) |
| `DXFOUTVERSION` | audits the written file and prints the result (`DXFConformance.audit`): group-code value types, SECTION/TABLE/BLOCK nesting, required sections and tables of the version, unique handles below `$HANDSEED`, owner (330) references, and entity references to layers, linetypes, text styles, dimension styles and blocks. `DXFConformance.entityCounts` lists the ENTITIES by type |
| Point cloud import (`IMPORTFILE`, `POINTCLOUDIMPORT`, `.las`, `.xyz`, `.pts`, `.txt`, `.ply`) | files above 48 MB (`PointCloudStream.streamThreshold`) are memory-mapped and sampled out of core: evenly spaced LAS records and binary-PLY vertices are addressed directly, text files are sampled at evenly spaced byte offsets with the point count estimated from the mean line length; memory use follows the point budget (`POINTLIMIT`), not the file size (`PointCloudStream.sample`, `PointCloudStream.load`) |

## 13. Validation, permissions and georeferenced content (round 12)

| Command / option / tool | What it does |
| --- | --- |
| `archi-cli --validate FILES… [--schema IFC2X3\|IFC4\|IFC4X3] [--json]` | validates exchange files: IFC / IfcZIP / ifcXML (schema tables and EXPRESS WHERE rules), DXF (group-code conformance audit + read-back), gbXML (XSD requirements) and `.archi` drawings (save/reopen round trip plus their IFC export in the chosen schema and their DXF export). Exit 0 all valid, 1 a file has errors, 2 a file cannot be read (`FileValidation`) |
| MCP tool `validate_file` | `{path, schema?}` → `{file, format, valid, errors, warnings, summary, issues: [{severity, code, message, location}]}` |
| MCP tool `ifc_validate` | now takes `schema` and `modelView` for the model's own export, and each issue on the own export lists `elements` (drawing ids to zoom to) |
| IFC WHERE rules | issue codes `WR-<Entity>.<Rule>` (`IFCWhereRules.swift`): points / directions / placements (dimensionality, parallel axes, `IfcCorrectLocalPlacement`), polylines and poly loops, indexed poly curves, B-spline control points, tessellations, parameterised profiles (rectangle, circle, C/I/L/T/U/Z, hollow), arbitrary profiles with voids, extrusions, `IfcShapeRepresentation` items vs. `RepresentationType`, contexts, SI and named units, compound plane angles, project, aggregation / containment / voids, zones, material associations, material layers (`HasMaterialLayerSetUsage`), property sets and lists, quantities, addresses, actor roles, USERDEFINED predefined types, text literals and fonts, lining properties, rigid operations. The checks are regression-tested against IfcOpenShell's `pass-*` / `fail-*` rule fixtures |
| `CENTRAL Permissions Show/Role/Layer/Default/Check` | see §9 — signed access policy enforced on synchronisation |
| DXF export | fit-point splines are written as real `SPLINE` entities (interpolating cubic + fit points); every entity of the R12…R2018 exports of the demo projects is read back by LibreCAD's libdxfrw reader |
| PDF output without the app (`archi-cli --out plan.pdf`, `--convert pdf`, batch/automation outputs, MCP `export` pdf) | `PDFWriter`: every sheet with content plotted at true scale on its paper (viewports clipped, paper-space annotation, title block), or the current level's plan on A3 at the largest standard scale that fits; plotted line weights and dashes, even-odd fills, Helvetica text, embedded JPEGs. `PDFWriter.objects(doc, ids:)` makes a PDF of a selection (Copy as PDF) |
| IFC export of imported objects | objects imported from IFC as meshes (props `ifcType` / `ifcGuid`) are exported again as their IFC class (or `IfcBuildingElementProxy` with the class in ObjectType when the target schema lacks it) with their original GlobalId, so import → export keeps every product's GlobalId |
| Drag and drop / paste | dropped GeoJSON, shapefiles, OSM, CityJSON, terrain grids, point clouds, survey point tables and world-file images keep their georeferenced position (project location) instead of the drop point (`ExternalContent.isGeoreferenced`); pasted GeoJSON text is placed on the map the same way |

## 14. Rhino 3DM and SketchUp (IO-044, IO-043)

- **Import `.3dm`** (`import_file`, `IMPORTFILE`, `RHINOIN`/`3DMIN`, the Import dialog, `archi-cli model.3dm --out …`):
  3DM versions 2–8. Meshes; B-reps from Rhino's cached render meshes, or — when the file was saved without them, or with
  `RHINOIN` → `Tessellate` — by tessellating each trimmed face (NURBS, plane, revolution and sum surfaces; trim loops
  sampled in the parameter plane, constrained Delaunay triangulation); lightweight extrusions (capped, with holes);
  untrimmed surfaces; curves (lines, arcs and circles, polylines and NURBS splines stay exact when parallel to XY, else
  3D polylines with `vertexZ`); points and point clouds; blocks (instance definitions, nested) are exploded. Layers keep
  full `Parent::Child` names, colours, visibility and locking; object colours, V4/V5 render materials and the unit
  system (scaled into the drawing units). Props: `rhinoId`, `rhinoType`, `name`, `material`.
- **Export `.3dm`** (`export` with `format: "3dm"`, `RHINOOUT`/`3DMOUT`, `--out model.3dm`, batch jobs): a version 4
  archive (opens in Rhino 4–8): unit system and tolerances, layers, the 3D model as meshes with normals coloured by
  material (object colour, name "Element — Material"), drafting curves as exact lines, arcs/circles, polylines (bulges as
  poly curves of lines and arcs), NURBS splines and hatch boundaries at their elevation. Text, dimensions, tables and
  images are not written. `Rhino3DM.exportWithReport(doc)` returns counts.
- **SketchUp `.skp`**: the format is closed (only Trimble's proprietary SDK reads it), so `import_file` identifies the
  file (`SketchUpImport.header` → version) and converts it with a user-installed converter named by the `SKPCONVERTER`
  variable or `ARCHI_SKP_CONVERTER` environment variable, run as `converter input.skp output.dae` (it may write .dae,
  .3dm, .obj, .fbx or .gltf); the output goes through the matching importer. Without one the error explains how to
  export COLLADA or 3DM from SketchUp. `SketchUpImport.preview(data)` returns the embedded PNG thumbnail if present.


### Section sheet graphics (1.0.1)

`SECTIONSTYLE` (`SECSTYLE`, `SSTYLE`) is a core command available through `archi.command`
and `command.run`. Example: `SECTIONSTYLE Set "Sheet 1" "color:red;fill:0.7,0.7,0.7;cut:0.5;proj:0.25;shading:off"`.
`List` reads the named sheet style; `Reset` restores project defaults. Each change is one undo step.
Section viewports on the named sheet use these graphics in the Mac composer and portable plot
writer; model views, plans and other sheets retain their own settings.

### Named page setups

`PAGEPRESET` (`PSPRESET`, `NAMEDPAGESETUP`) supports Save, Apply, Import, Delete and List as shown in the User Guide. `Apply` accepts `All` or a quoted `|`-separated list of sheet names. It validates all targets before modifying the document. Saved presets include paper dimensions, plot settings, section graphics and referenced custom plot tables. Import reads `.archi` files; conflicting plot tables get unique names. All changes support undo and save/reopen.

The portable engine exposes `pagepresets.list`, `pagepresets.apply` (`name` and `layouts: [index]` or `all: true`), `pagepresets.delete` (`name`) and `pagepresets.import` (`path`). `pagesetup.get` includes `presets`, `layouts`, `hasSection` and `sectionStyle`. `pagesetup.set` accepts `sectionStyle` (null removes an override), `presetName` (save current settings), `presetOnly: true` (save the draft without applying to the source sheet), and `presetSource` (resolve imported preset pens). Section style uses the Codable SectionSheetStyle object: `shaded` and `lines` with colour/fill RGBA and weights in millimetres.
