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
| `export` | `path`, `format?`, `level?` | dxf, dxf12, svg, ifc, ifczip, obj, stl, glb, 3mf, usda, usdz, step, ply, plt (HP-GL/2), xlsx, csv, geojson, points, analytical, opensees (Tcl), gbxml, cobie, dae, fbx, igs (IGES), dgn (V7), laser (CNC/laser SVG), html (read-only viewer), archit (git-friendly text), dwg (converter needed), archi |
| `list_commands` | `category?` | available commands |
| `undo` | – | undo last change |
| `import_file` | `path`, `format?`, `offset?` | merge .archi, .archit, .dxf, .dwg (converter), .ifc/.ifczip, .svg, .obj, .stl, .3mf, .gltf/.glb, .fbx, .usd/.usda/.usdz, .igs/.iges, .dgn (V7), .pdf (vectors and text), .dwfx, .ply, .off, .amf, .dae, .step, .geojson, .cityjson, .shp, .osm, .asc, .xlsx, CSV points, XYZ/PTS or LAS point clouds into the document |
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
| `ifc_validate` | `path?` | IFC checks (syntax, schema, references, GlobalIds, attribute counts, units, containment) of a file or the model |
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
