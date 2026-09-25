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
| `export` | `path`, `format?`, `level?` | dxf, dxf12, svg, ifc, ifczip, obj, stl, glb, 3mf, usda, usdz, step, ply, plt (HP-GL/2), xlsx, csv, geojson, points, analytical, gbxml, cobie, dae, dwg (converter needed), archi |
| `list_commands` | `category?` | available commands |
| `undo` | – | undo last change |
| `import_file` | `path`, `format?`, `offset?` | merge .archi, .dxf, .dwg (converter), .ifc/.ifczip, .svg, .obj, .stl, .3mf, .gltf/.glb, .ply, .off, .amf, .dae, .step, .geojson, .cityjson, .shp, .osm, .asc, .xlsx, CSV points or XYZ/PTS point clouds into the document |
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

Batch conversion (one line per file; exit status 1 when any file failed):

```sh
archi-cli --convert dxf plans/*.archi --outdir out/        # also ifc, ifczip, step, glb, obj, stl, 3mf, svg, xlsx, gbxml, cobie, dae, archi …
archi-cli --convert archi survey/*.dxf site.ifc            # inputs may be any importable format
```
