# archi-engine protocol

`archi-engine` is the Oanarina Archi Tool engine (ArchiCore: documents, all engine commands, undo, snaps, grips,
draw lists, meshes, file formats) as a process. The Windows shell starts one engine per window and talks to it with
**newline-delimited JSON-RPC 2.0 over stdin/stdout**: one JSON object per line, UTF-8, `\n` line ends. Diagnostics go
to stderr. The engine is portable Swift (Foundation + ArchiCore only) and builds on Windows, Linux and macOS.

Source: `app/Sources/ArchiCore/Host/` (session, JSON, draw list and mesh encoders, panels, render presets) and
`app/Sources/archi-engine/main.swift` (stdio loop). Tests: `app/Tests/ArchiCoreTests/EngineSessionTests.swift`.
Recorded exchanges for the shell: `./scripts/q.sh engine` writes `build/engine-fixtures/*.json` (see the end).

```
archi-engine [--open <file>] [--cwd <folder>]     # serve on stdio; relative paths resolve against --cwd
archi-engine --fixtures <folder> --sample <file>  # record the shell fixtures, then exit
archi-engine --version
```

## Framing

- Request: `{"jsonrpc":"2.0","id":N,"method":M,"params":{...}}` → response `{"jsonrpc":"2.0","id":N,"result":...}` or
  `{"jsonrpc":"2.0","id":N,"error":{"code":C,"message":"..."}}`. Requests are answered in order.
- A request without `id` is executed but not answered.
- Engine notifications have no `id`. Notifications caused by a request are written **before** its response.
- Error codes: `-32700` parse error, `-32600` invalid request, `-32601` method not found, `-32602` invalid params,
  `-32000` engine failure (file not found, nothing to save to …).
- Numbers are rounded to 6 decimals; integers print without a decimal point. Colours are `"#rrggbb"` with an
  `"alpha"` field next to them when not opaque. Points are `[x, y]` (or `[x, y, z]`) in drawing units (the document's
  `units`, millimetres for the samples; sheets use paper millimetres). Angles are radians unless named `…Altitude`,
  `…Azimuth`, `beam`, `northAngle` (degrees).

On start the engine writes `{"jsonrpc":"2.0","method":"ready","params":{"version":"1.0.0","protocol":"1.0"}}`.

## Notifications

| method | params | when |
|---|---|---|
| `log` | `{"text":"Command: LINE"}` | every line the Mac command-line history shows (prompts, results, errors) |
| `prompt` | prompt state (below) | the command prompt changed (coalesced) |
| `changed` | `{"what":["document","selection","sysvars"]}` | refresh views / panels (coalesced) |
| `host` | `{"action":"zoomExtents"}` … | a command asks the UI for something (below) |

`host` actions: `open`, `saveAs`, `export` (`format`), `plot`, `import` (a file dialog is needed: answer with
`doc.open` / `doc.save` / `file.export` / `file.import`), `zoomExtents`, `zoomWindow` (`rect`), `zoomScale` (`scale`),
`pan` (`delta`), `regen`, `show2D`, `show3D`, `showSplit`, `render`, `walkthrough`, `showPanel` (`panel`),
`setViewStyle` (`style`), `setView` (`view`). Commands given a path (`SAVEAS C:\x.archi`, `EXPORT …`) are handled by
the engine itself.

## Prompt state

Returned by `command.run`, `input.*` and sent as the `prompt` notification:

```json
{"active":true,"command":"LINE","message":"Specify next point [Undo]:","label":"Specify next point",
 "keywords":["Undo"],"kinds":["point","keyword"],"base":[-25000,-30000],
 "preview":[{"type":"stroke","points":[[-25000,-30000],[-25000,-30000]],"closed":false,"style":{"color":"#dbe0eb","lineweight":0,"dash":[]}}]}
```

- `message` is the command-line prompt exactly as the Mac shows it (`"Command:"` when idle); `label` without keywords
  and default. `defaultValue` appears when the prompt has one, `transparent` while a transparent command ('ZOOM) runs,
  `rotatable` when Space turns the drag preview 90°.
- `kinds` ⊂ `point, distance, angle, integer, string, selection, entity, keyword`.
- `base` is the rubber-band base point (draw the rubber line from it to the cursor, as the Mac canvas does).
- `preview` is the command's live preview geometry (draw items, hairline, colour `#dbe0eb`) at the last cursor.

## Methods

### engine.hello `{}`
```json
{"name":"archi-engine","version":"1.0.0","protocol":"1.0","platform":"windows","methods":["engine.hello","doc.new",…],
 "commands":[{"name":"3DALIGN","aliases":["ALIGN3D","3DAL"],"category":"3D","summary":"Aligns solids in 3D by up to three source…","modifies":true},…],
 "sysvars":[{"name":"ANGDIR","kind":"integer","default":"0","range":"0,1","summary":"Positive angle direction: 0 counterclockwise, 1 clockwise"},…]}
```
`commands` is the engine's command registry (ribbon, menus and command-line autocomplete are built from it).

### doc.new `{template?}` · doc.open `{path}` · doc.save `{path?, format?}` · doc.info `{}`
All return the document info:
```json
{"title":"Cedar House","path":"C:\\…\\Cedar House.archi","dirty":false,"units":"millimeters","unitAbbreviation":"mm",
 "levels":[{"id":0,"name":"Ground Floor","elevation":0,"height":3200},{"id":1,"name":"Upper Floor","elevation":3200,"height":3000}],
 "currentLevel":"Ground Floor","currentLevelId":0,"layouts":["Sheet 1"],"extents":[-10000,-18000,32000,20000],"empty":false,
 "project":"Cedar House","currentLayer":"0","entities":408,"elements":59,"canUndo":false,"canRedo":false}
```
`open` reads every format the Mac opens (`.archi`, `.archiz`, `.archit`, `.json`, `.dxf`, IFC and the importers);
non-native files open untitled. `save` writes by extension (default `.archi`). `extents` = ZOOM Extents of the current
level (`empty:true` and a 10 m square when nothing is drawn).

### command.run `{line, cancel?}` → prompt state
Runs a command line as if typed and Enter pressed (`"LINE"`, `"LINE 0,0 1000,0 "`, `"WALL"`…); spaces separate
inputs like AutoCAD. Returns when the command waits for input or ends. `cancel:true` first cancels a running command
(ribbon-button behaviour, like the Mac `AppModel.runCommand`).

### input.text `{text}` → prompt state
What the user typed in the command line followed by Enter (coordinates `100,200`, `@500<45`, distances, keywords,
text answers). At the idle prompt it starts a command.

### input.point `{x, y, snap?=true, pixelsPerUnit?}` → prompt state
A click in the drawing (world coordinates). With `snap` the engine applies running object snaps, grid snap and
ortho/polar from the base point, exactly as the Mac canvas (`CanvasView.updateCursorPoint`). On a selection / entity
prompt it picks the object under the point; at the idle prompt it adds it to the selection.

### input.cursor `{x, y, pixelsPerUnit?}` → prompt state + `cursor`, `snap`, `hover`
Mouse move. Returns the resolved (snapped) cursor, the snap marker `{"kind":"endpoint","point":[x,y],"entity":12}`
or `null`, the object under the cursor for hover highlight (`hover`), and the preview at that point:
```json
{"active":true,"command":"LINE","message":"Specify next point:",…,"base":[-30000,-30000],
 "preview":[{"type":"stroke","points":[[-30000,-30000],[-25000,-30000]],"closed":false,"style":{"color":"#dbe0eb","lineweight":0,"dash":[]}}],
 "cursor":[-25000,-30000],"snap":null,"hover":null}
```
Snap aperture is 10 px and pick aperture 6 px, converted with the last `pixelsPerUnit` sent.

### input.key `{key, text?}`
`Enter` / `Space` (answer the prompt with Enter; at the idle prompt repeat the last command), `Escape` (cancel the
command, or clear the selection when idle), `Tab` (`text` = what is typed → `completions` [{name, command, summary}]
and `text` = first match), `Up` / `Down` (command-line history recall → `text`).

### command.complete `{prefix}` → `[{name, command, summary}]`
Autocomplete list (most used first, then mid-string matches), as the Mac command line.

### view.drawList `{rect?, pixelsPerUnit?, level?, layout?, options?}`
Plan (model space) of a level: `level` = id, name or `"all"` (default the current level); `rect` = `[x0,y0,x1,y1]`
visible window (items of objects outside it are left out); `options` = `{showElements, showAnnotations, forPaper,
cutHatches, reflectedCeiling, showCeilings, linetypeScale}`.
```json
{"items":[{"type":"fill","loops":[[[150,1650],[5850,1650],[5850,9850],[150,9850]]],"color":"#ffaf82","alpha":0.06,"id":51},
          {"type":"text","text":{"position":[3745.898438,7794.914063],"height":220,"rotation":0,"content":"Living","style":"Standard","halign":"center","valign":"bottom","width":0},"font":"Helvetica","color":"#d1ac9c","id":51},
          {"type":"stroke","points":[[-30000,-30000],[-25000,-30000]],"closed":false,"style":{"color":"#ffffff","lineweight":0.25,"dash":[]},"id":468}],
 "count":974,"bounds":[-10000,-18000,32000,20000],"level":0,"selection":[],"grid":{"show":true,"spacing":100}}
```
Draw items are `Render/DrawList.swift` `DrawItem` with its field names:
- `stroke` — `points`, `closed`, `style` {`color`, `alpha`?, `lineweight` (plotted mm; 0 = hairline), `dash` (drawing
  units: positive dash, negative gap, 0 dot; empty = continuous)};
- `fill` — `loops` (even-odd rule), `color`, `alpha`?;
- `text` — `text` (TextGeom: `position`, `height`, `rotation`, `content`, `style`, `halign` left|center|right,
  `valign` baseline|bottom|middle|top, `width` wrap width, 0 = none), `font`, `color`;
- `image` — `image` (ImageGeom: `path`, `origin`, `size`, `rotation`).
`id` is the object the item belongs to (selection highlight, hover); missing for decoration. Paint in list order.

With `layout` (sheet name or index) the result is a sheet in paper millimetres:
`{"layout","paper":{"name","width","height"},"viewports":[{"index","rect","scale","ratio","view","level","title"}],
"titleBlock":{"Project":…,"Sheet":…},"items":[…],"count"}`; viewport items carry `"clip":[x0,y0,x1,y1]`.

### pick `{x, y, tolerance?, add?=true, toggle?}` · select.window `{x0,y0,x1,y1, crossing?, add?, remove?}`
### select.set `{ids}` · select.get `{}`
Return `{"ids":[1],"summary":"1 object: wall","types":[{"type":"wall","count":1}],"hit":1,"prompt":{…}}`.
Plain click = `pick` (adds, like the Mac); Shift-click = `toggle:true`; window right-to-left = crossing (default from
the corner order). During a selection prompt (ERASE, MOVE …) `pick` / `select.window` answer the prompt instead.

### grips.get `{}` → `[{"id":1,"index":0,"x":0,"y":1500,"kind":"element"},…]`
Grips of the selection (GRIPS / GRIPOBJLIMIT honoured). `kind`: `vertex, midpoint, center, quadrant, insertion,
textWidth, dimOrigin, dimText` for drafting objects, `element` for BIM elements.
### grips.drag `{id, index, x, y, mode?, copy?, snap?=true}` → `{"changed":[ids],"grips":[…]}`
Commits a grip edit (one undo step); `mode` = `stretch|move|rotate|scale|mirror` (or ST/MO/RO/SC/MI).

### model.meshes `{level?, lod?, binary?}`
```json
{"meshes":[{"id":1,"kind":"wall","material":"Limestone","color":"#ded6c4","opacity":1,"roughness":0.88,"metalness":0,
            "vertexCount":224,"triangleCount":84,"positions":"AAAWwwDA…","normals":"AAAAgAAA…","indices":"AwAAAAEA…",
            "uvs":"mpkZvs3M…","texture":"textures/limestone.jpg","textureScale":1200,"edges":"AAAWwwDA…"},…],
 "lights":[{"id":80,"kind":"spot","position":[x,y,z],"target":[x,y,z],"lumens":2500,"cct":3000,"beam":110,"size":[1,1],"fixture":true}],
 "sun":{"azimuth":222,"altitude":46,"direction":[x,y,z],"preset":"Daylight"},"units":"millimeters","bounds":[[x,y,z],[x,y,z]]}
```
Buffers are little-endian base64: `positions`/`normals` Float32 xyz, `indices` Uint32 triangles, `uvs` Float32 uv,
`edges` Float32 line-segment pairs (THREE.LineSegments). Model units, **Z up** (three.js: rotate −90° about X, or set
`camera.up = (0,0,1)`). `level` = id/name/`"all"` (default all); with a level only BIM elements on it are sent.
`lod` 0 = full detail, 1 and 2 = coarser (MeshLOD 30 % / 8 % of the triangles). `opacity` = 1 − material transparency,
`emissive` appears for MATEMIT materials. `texture` paths are relative to the drawing (the Cedar House textures are in
`assets/demo/textures`). The Cedar House trees are ~1.1 M triangles (~160 MB as base64): pass `"binary":"<file>"` to
get every buffer written to that file, each buffer then described as `{"offset":N,"length":bytes}`.

### render.settings `{}` · render.preset `{name}`
The photographic presets of the Mac Realistic view (`ArchiApp/BeautyLighting.swift`), same values:
```json
{"preset":"Golden hour","keyword":"Goldenhour","sky":"golden","sunAltitude":11,"sunAzimuth":228,"sunDirection":[-0.729491,-0.656837,0.190809],
 "sunColor":[1,0.66,0.38],"sunIntensity":3400,"shadowRadius":5,"shadowAlpha":0.9,"envIntensity":0.95,"ambient":0,"exposure":0.75,
 "whitePoint":1.7,"bloom":0.22,"bloomThreshold":0.95,"saturation":1.1,"contrast":0.08,"ao":0.9,"windowGlow":0.12,"artificial":0.3,
 "lampGlow":1,"northAngle":0,"presets":["Daylight","Golden hour","Overcast","Night"]}
```
`name`: Daylight, Goldenhour, Overcast, Night (lenient: "golden hour", "sunset", "cloudy" …). Stored in the drawing
(RENDERPRESET variable) as one undo step. `sunColor` is linear RGB; `sunIntensity` is SceneKit lux-like units (scale
for three.js); `shadowRadius` is in shadow-map texels.

### panel.layers / panel.levels / panel.properties / panel.materials / panel.sheets / panel.history `{}`
- layers: `{"current","layers":[{name,color,linetype,lineweight,visible,frozen,locked,plot,transparency,description,count,current,canDelete}],"linetypes"}`
- levels: `{"current","currentId","units","levels":[{id,name,elevation,height,elements,current,canDelete}]}` (highest first)
- properties: selection → `{"ids","summary","types","rows":[{"name","value","readOnly"}]}` (`*VARIES*` where objects
  differ); no selection → `{"project":{name,number,client,address,author},"drawing":{units,currentLayer,currentLevel,objects,elements,layers,blocks,file}}`
- materials: `{"materials":[{name,color,roughness,metalness,transparency,texture,textureScale,cutPattern,uses}]}`
- sheets: `{"current":"Model","sheets":[{index,name,paper:{name,width,height},viewports,titleBlock}],"papers":[…]}`
- history: `{"undo":[labels],"redo":[labels],"canUndo","canRedo","undoLabel","redoLabel","commands":[command lines],"dirty"}`

### panel.set `{panel, key, value}` → the panel again
Each edit is one undo step with the Mac panel's label.
- layers: `current`, `new`, `delete`, `<layer>.name|visible|frozen|locked|plot|color|linetype|lineweight|transparency|description`
- levels: `current`, `new`, `delete`, `<level>.name|elevation|height`
- properties: `<property name>` (applies to the selection) or `project.name|number|client|address|author`
- materials: `new`, `<material>.color|roughness|metalness|transparency|texture|textureScale|cutPattern`
- sheets: `current` (sets CTAB), `new`, `delete`, `<sheet>.name|paper`
- history: `undoTo` = number of undo steps to keep

### edit.undo / edit.redo `{}` → panel.history result
Cancels a running command first.

### sysvar.get `{name}` · sysvar.set `{name, value}`
`{"name":"OSMODE","value":"4287","kind":"integer","readOnly":false,"summary":"…"}`; values as SETVAR (settings such as
ORTHOMODE, OSMODE, GRIDMODE map to the drafting settings).

### file.export `{path, format?, level?}` → `{path, format, bytes}` · file.import `{path, format?, offset?}`
Export by extension or `format` (dxf, dwg via converter, ifc, pdf, svg, obj, stl, glb/gltf, 3mf, usdz, csv …).
Import merges the file into the drawing as one undo step → `{summary, entityIds, elementIds}`.

### engine.log `{limit?}` → `{"lines":[…]}`
The last command-history lines (for a new window attaching to a running engine).

## A complete LINE exchange (from `build/engine-fixtures/line-sequence.json`)

```
→ {"jsonrpc":"2.0","id":5,"method":"command.run","params":{"line":"LINE"}}
← {"jsonrpc":"2.0","method":"log","params":{"text":"Command: LINE"}}
← {"jsonrpc":"2.0","method":"log","params":{"text":"Specify first point:"}}
← {"jsonrpc":"2.0","method":"prompt","params":{"active":true,"command":"LINE","message":"Specify first point:",…}}
← {"jsonrpc":"2.0","id":5,"result":{"active":true,"command":"LINE","message":"Specify first point:","label":"Specify first point","keywords":[],"kinds":["point"],"preview":[]}}
→ {"jsonrpc":"2.0","id":6,"method":"input.point","params":{"x":-30000,"y":-30000,"snap":false}}
← … {"jsonrpc":"2.0","id":6,"result":{"active":true,"command":"LINE","message":"Specify next point:",…,"base":[-30000,-30000],…}}
→ {"jsonrpc":"2.0","id":7,"method":"input.cursor","params":{"x":-25000,"y":-30000,"pixelsPerUnit":0.05}}
← {"jsonrpc":"2.0","id":7,"result":{…,"preview":[{"type":"stroke","points":[[-30000,-30000],[-25000,-30000]],…}],"cursor":[-25000,-30000],"snap":null,"hover":null}}
→ {"jsonrpc":"2.0","id":8,"method":"input.point","params":{"x":-25000,"y":-30000,"snap":false}}
← {"jsonrpc":"2.0","method":"changed","params":{"what":["document"]}}
← {"jsonrpc":"2.0","id":8,"result":{"active":true,"command":"LINE","message":"Specify next point [Undo]:","keywords":["Undo"],"kinds":["point","keyword"],…}}
→ {"jsonrpc":"2.0","id":9,"method":"input.key","params":{"key":"Enter"}}
← {"jsonrpc":"2.0","id":9,"result":{"active":false,"message":"Command:","label":"Command","keywords":[],"kinds":[],"preview":[]}}
→ {"jsonrpc":"2.0","id":14,"method":"no.such.method","params":{}}
← {"jsonrpc":"2.0","id":14,"error":{"code":-32601,"message":"Method not found: no.such.method"}}
```

## Fixtures for the shell

`./scripts/q.sh engine` (Mac bridge) builds the engine, replays `scripts/engine-smoke.jsonl` into
`build/engine-smoke.out.jsonl` and records `build/engine-fixtures/` from the Cedar House sample. Each file is
`{"request":…,"response":…,"notifications":[…]}` (or an array of them for sequences):
`hello`, `doc-open`, `doc-info`, `drawlist-cedar` (current level on its extents at 0.05 px/mm), `drawlist-level-1`,
`drawlist-sheet` (a plan viewport at 1:200 on Sheet 1), `meshes-all-lod2`, `meshes-level-0`, `render-settings`,
`render-presets`, `panel-*`, `select-set`, `panel-properties-wall`, `grips-get`, `sysvar-get`, `line-sequence`,
`command-complete`, `error-unknown-method`, and `index.json`.

## Not in the engine (the shell or the Mac UI layer does it)

Commands the Mac defines in its UI layer (ArchiApp: views, dialogs, render window, plotting through Core Graphics,
scripting console) are not in the engine's registry; `RENDERPRESET` has a portable version registered by
archi-engine. The script console's `archi` API runs in the shell's JavaScript and calls this protocol.
