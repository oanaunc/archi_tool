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
`assets/demo/textures`). The Cedar House trees are ~1.1 M triangles (~160 MB as base64): pass `"binary":"<file>"` (or
`true` for a temporary file the engine picks) to get every buffer written to that file, each buffer then described as
`{"offset":N,"length":bytes}`, plus `"binary"`, `"binaryLength"` and `"layout"` in the result. BIM meshes carry `"level"`.

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

### Dialogs (Host/EngineDialogs.swift): the Mac sheets that edit the drawing
Same fields, defaults, validation and undo labels as the Mac (`UnitsSheet`, `DraftingSettingsSheet`, `QuickSelectSheet`,
`LayerStatesSheet`, the Layers panel, `PageSetupSheet`, `TemplateLibrary`).
- `units.get {units?, lunits?, luprec?, aunits?, auprec?}` → `{units, lunits, luprec, aunits, auprec, unitList:[{value,title,abbreviation,mm}],
  linearTypes, angularTypes, linearPrecisionLabel, angularPrecisionLabel, sample, note}`; the params preview other values
  (live sample, e.g. `"Sample: 3'-6 1/2\"  ·  45°"`) without changing the drawing.
- `units.set {units, lunits 1–5, luprec 0–8, aunits 0–4, auprec 0–8}` → units.get; one "Units" undo step when anything changed.
- `drafting.get {}` → the session's DraftSettings `{showGrid, gridSnap, gridSpacing, ortho, polarTracking, polarIncrement, dynamicInput,
  lineweightDisplay, textHeight, wallThickness, wallHeight, objectSnap, snapModes, snapKinds, polarIncrements, units}`;
  `drafting.set {…any of those}` (positive numbers, known snap names) → drafting.get.
- `drafting.defaults {units?, draft:{…}}`: Settings ▸ Drafting defaults for a new or open drawing (AppPreferences.draftDefaults: grid
  spacing given in mm is converted for metric drawings, polar tracking off with ortho); `units` (Settings ▸ General ▸ Default units)
  relabels a new blank drawing and scales the text/wall defaults like AppModel.newDocument.
- `qselect.options {}` → `{types:[{value,title}], properties, operators, layers, selectionCount, scope}`;
  `qselect.run {scope 0 current level | 1 selection, type, property, op, value, apply?, mode New|Append|Exclude}` → `{count}` (live
  count) or, with `apply`, `{count, selected, ids}` and the history line `QSELECT <type> <criterion> → n matched; m selected.`
- `layerstate.list` → `{states:[{name, layers, date (ISO), description, currentLayer}]}`; `layerstate.save|restore|delete {name}`,
  `layerstate.rename {name, newName}` → `{states, selected?, changed?}` (undo steps "Save/Restore/Delete/Rename Layer State").
- `layerfilter.list` → `{filters:[{name, filter}]}` (document variables `LAYERFILTER:<NAME>`, "#on #used #unlocked A-*");
  `layerfilter.save {name, filter}`, `layerfilter.delete {name}`.
- `layers.group {group, key: visible|frozen|locked, value}` → `{changed}`: layer-tree bulk toggle ("Layer Group <name>"; group = name
  prefix before - _ or space, "xref|", "(Standard)"); the current layer is never frozen.
- `pagesetup.get {layout?}` (sheet index or name; absent = model) → `{isSheet, layout, title, paper?, portrait?, papers:[{name,width,height,
  label,modelLabel}], setup:{colorMode, lineweightScale, plotStamp, stampText?, modelPaper, modelPortrait, modelScale?, plotStyleTable?,
  namedStyleTable?, plotArea, plotWindow?, exactFit}, scaleText, colorModes, plotAreas, tables, namedTables, scales, stampTemplate, stampFields}`.
  `pagesetup.set {layout?, setup:{…}, scaleText?, paper?, portrait?}`: one "Page Setup" undo step; stored as the Mac PageSetup JSON in
  `PAGESETUP:<SHEET>` / `PAGESETUP:*MODEL*` (removed when default); a sheet also gets its paper ("A1 portrait" swaps the sides).
- `templates.list {folder?, recent?}` → `{folder, templates:[{id, name, subtitle, symbol, recent?}]}`: `builtin:metric`,
  `builtin:metricArchitectural`, `builtin:imperial`, `builtin:building`, the .archi/.architemplate files of the folder, then the
  recent template files that still exist ("Recent · <folder>"). `templates.new {id}` → doc info (new untitled drawing);
  `templates.save {name, folder?}` → `{path}` (`<name>.architemplate`).
- `ui.prefs {values:{…}}` → every stored value: application settings the portable UI commands use as prompt defaults
  (`cursorSize`, `autosaveMinutes`, `theme`, `templatesFolder`, `workspaces` "a|b", `workspace`, `cui` JSON, `quickAccess` "A,B").

### Portable UI commands (Host/EngineUICommands.swift) and their `host` actions
archi-engine registers portable versions of the Mac UI-layer commands with the same names, aliases, prompts and messages:
`OPTIONS` (`OP`, `PREFERENCES`, `SETTINGS`, `CONFIG`; page keyword), `AGENTSETTINGS`, `CURSORSIZE`, `SAVETIME`, `THEME`,
`QSELECTDIALOG`, `LAYERSTATE` (adds the default `Dialog` option to the core command), `LAYERFILTER`, `WSCURRENT`, `WSSAVE`, `CUI`
(Dialog/Add/Remove/Hide/Show/List/Export/Import/Reset), `PAGESETUP`, `NEWFROMTEMPLATE`, `SAVEASTEMPLATE`. Where the Mac opens a
window they send a `host` notification the shell answers with its dialogs:
- `{"action":"dialog","dialog":"options","tab":"Drafting"}` — also `quickSelect`, `layerStates`, `pageSetup`, `cui`;
- `{"action":"preference","key":"cursorSize"|"autosaveMinutes"|"theme","value":…}`;
- `{"action":"workspace","name":…}`, `{"action":"workspaceSave","name":…}`;
- `{"action":"cui","op":"set","data":{format:"oanarina-archi-cui",…},"quickAccess"?:[…]}`;
- `{"action":"layerFilter","filter":"#on A-*"}` ("" clears); `{"action":"newWindow","kind":"template","path":<template id>}`.
`showPanel` names that are dialogs on the Mac (`Units`, `Drafting Settings` from UNITS / DSETTINGS) open the same dialogs.

### Tool windows (Host/EngineToolDialogs.swift, EngineScripting.swift, EngineMCP.swift): part B of the Windows port
Methods behind the Mac tool windows. Edits are one undo step each (the label is given below) and send `changed`.
- `script.call {fn, args}` — the `archi` API of the script console, plugins and agents: `run(lines)`, `doc`, `summary`,
  `entities(filter?)`, `elements(filter?)`, `get(id)`, `add(obj|[obj])`, `addElement(obj)`, `update(id, patch)`, `remove(ids)`,
  `select(ids)`, `selection`, `setVar`, `getVar`, `layers`, `levels`, `wall`/`door`/`window`/`opening`/`slab`/`room`/`column`,
  `undo`, `redo`, `commands`, `evaluateGraph(graph)`, `bakeGraph(graph)`, `registerCommand(name, fnName, opts, source, script)`.
  Objects use the `.archi` JSON of entities and elements (ScriptJSON). A script error is `-32000` with the message.
- `agent.call {method, params}` · `agent.methods {}` — the agent server's JSON-RPC methods (`list_methods`, `run_command`,
  `get_document`, `get_document_summary`, `list_entities`, `list_elements`, `add_entity`, `add_element`, `update_entity`,
  `delete`, `select`, `get_selection`, `export`, `list_commands`, `undo`, `redo`, resources, prompts, `list_tools`,
  `call_tool`). `eval_js` and `screenshot` answer `-32601` "answered by the shell": the shell runs them (script worker,
  plan PNG). `archi-engine <file.archi> --mcp` serves the same tools as an MCP server over stdio (Claude Desktop / Code).
- `graph.get` · `graph.evaluate {graph, preview?:"plan"|"3D", kinds?, script?}` · `graph.bake {graph, label?, store?}` ·
  `graph.save {name, graph}` · `graph.load {name}` · `graph.delete {name}` · `graph.script {graph}` — node editor and graph
  player (NodeGraph evaluation is portable, ArchiCore/Script/NodeGraph.swift); evaluate returns the draw list / meshes
  of the result without changing the drawing, bake adds it ("Bake Graph").
- `library.scan {folder, recursive?}` · `library.preview {file, block?}` (draw list + bounds) ·
  `library.insert {file, block?, x, y}` · `blocks.list` — Block Library.
- `doc.edit {label, ops:[…], merge?}` with ops `setVariable {name, value}`, `setInfo`, `setTitleBlock`, `setMaterial`,
  `addMaterial`, `removeMaterial`, `renameMaterial {name, to}`, `assignMaterial {ids, material}` · `doc.variables {prefix|prefixes}` ·
  `material.list` (materials with uses, maps, render assets, bump; patterns; library folder) — Materials panel and editor.
- `sheetset.get` · `sheetset.edit {op, …}` (`new`, `duplicate`, `move {index, by}`, `delete`, `rename`, `renumber {start}`,
  `index`, `viewTitles`, `addRevision {code, description, date}`, `deleteRevision`) · `titleblock.get {layout}` ·
  `titleblock.apply {layout, fields, info, logo?, applyToAll?, sheetCustom, projectCustom}` — Sheet Set Manager, Title Block.
- `markup.list` · `markup.edit {op: reply|status|remove|addAroundSelection, id?, text?, resolved?, title?, comment?}` ·
  `compare.run {path}` (added/removed/modified shapes with polylines, colours, counts, layers, CSV) ·
  `compare.save {path, out}` · `revcloud.list` · `revcloud.add {layout, code, note, viewport? | rect:[x,y,w,h]}` ·
  `revcloud.remove {id}` — Markups, Compare Drawings, Revision Clouds.
- `family.list` · `family.get {name}` · `family.template {template}` · `family.evaluate {draft, original?, type?, flex?, preview?}`
  (problems, resolved values, preview meshes and bounds) · `family.apply {draft, original?}` · `family.delete {name}` —
  Family Editor. `customizer.get` · `customizer.set {id, name, value}` — Customizer of the selected scripted object.

Portable commands (Host/EngineToolCommands.swift) with the Mac names and aliases ask the shell with `host` notifications:
`BLOCKPALETTE` → `{"action":"dialog","dialog":"blockLibrary"}`, `MATBROWSER` → `materialLibrary`, `TITLEBLOCK` →
`titleBlock {layout}`, `MARKUPPANEL` → `markups`, `COMPAREPANEL` → `compare`, `REVCLOUDPANEL` → `revisionClouds`,
`FAMILYPANEL` → `familyEditor {family}`, `CUSTOMIZERPANEL` → `customizer`, `NODEEDITOR` → `nodeEditor`, `GRAPHPLAYER` →
`graphPlayer`, `CONNECTCLAUDE` → `connectClaude`; `MATERIALS` and `SHEETSET` → `showPanel`; `SCRIPTCONSOLE` →
`{"action":"scriptConsole"}` (show/hide), `SCRIPTLIBRARY` → `scriptLibrary`, `TUTORIALRECORD` / `TUTORIALS` →
`{"action":"tutorials","mode":"List"|"Check"|"Record"|"Open"}` (Windows opens the tutorial videos on the website).
Plugin commands registered by scripts send `{"action":"runScript","source","function","plugin","script"}` and
`changed {"what":["commands"]}`. `SHEETINDEX` and `SHEETREVISION` run in the engine.

### Canvas (Host/EngineCanvas.swift, EngineCanvasCommands.swift): the 2D canvas of the Windows shell
Methods behind the parts of the Mac `PlanCanvasView` (CanvasView.swift) and `SheetCanvasNSView` (SheetView.swift) that read or
edit the drawing. Edits are one undo step each with the Mac label; `input.cursor` also returns `tracking`
(`{points, lines:[{from,to}]}` of object snap tracking, or null), `dynamic` (dynamic-input fields `{length?, angle?, x, y,
relative, onFace}`) and, on a dynamic-UCS face, `ducs` (`[{from, to, color}]` axes at the crosshair).
- `canvas.state {}` → `{ucs:{origin, angle, world}, ucsIcon:{on, atOrigin}, twist (VIEWTWIST degrees), isometric, isoPlane, ducs,
  doubleClickEditing, grips, gripObjectLimit, selectionPreview, dynamicInput, dynMode, lastCommand, canUndo, canRedo, undoLabel,
  redoLabel, currentSheet, radialContext ("Drafting"|"Objects"|"Building elements"), maximizedViewport?}`.
- `canvas.view {center, scale, rect?, radialMenu?}`: the shell's plan view (VPMIN keeps its centre; pick apertures).
- `grips.actions {id, index}` → `[{action, title, immediate}]` multi-functional grip menu (empty for one option).
- `grips.preview {id, index, x, y, mode?, action?, turns?, reference?, snap?=true}` → `{point, origin, snap, reference, items}`:
  the resolved drag point (core grip stretch snaps, else running snaps / grid / ortho from the grip) and preview draw items.
- `grips.edit {id, index, x, y, mode?, action?, copy?, turns?, reference?, snap?=false}` → `{changed, grips}` ("Grip Edit",
  "Grip Edit + Rotate", "Grip Move Copy", "Add Vertex" …; joined wall ends follow). `grips.typed {id, index, mode, value, x, y,
  copy?}`: a value typed while the grip is hot (distance, degrees, factor).
- `select.lasso {points, remove?, crossing?}` (world points; clockwise = window, counter-clockwise = crossing; answers a
  selection prompt) → selection + `mode`, `found`. `select.modify {remove?, add?}` (selection cycling swaps one object),
  `pick.candidates {x, y, tolerance?}` → `{ids, types}` (canvas pick first), `select.chain {id | x,y}` → selection + `chain`
  (Tab: joined walls), `select.nudge {dx, dy, big?}` → `{moved, step, hint}` ("Nudge", arrow keys).
- `canvas.doubleClick {id}` → `{action: "textEditor" (text, content, singleLine, styleFont, format, color) | "textDialog"
  (content, multiline, message; leaders and dimensions) | "properties", command}`; `text.edit {id, content, height?, font?,
  bold?, italic?, underline?, color?}` ("Edit Text").
- `tempdims.get {id?}` → `[{id, index, reference, from, to, value, text, direction}]` of the single selected element;
  `tempdims.set {id, index, value}` ("Temporary Dimension").
- `flips.get {pixelsPerUnit?}` → `[{id, kind: facing|hand|wall, point, direction}]`; `flips.apply {id, kind}` ("Flip …").
- `palette.items {}` → `{blocks:[{name, item, shapes}], components:[{id, name, category, size, item, shapes}]}` (line
  thumbnails); `place.preview {item, x, y, turns?}` → `{items, degrees}`; `place.drop {item, x, y, turns?, hit?}` — items
  `archi-block:<name>`, `archi-component:<id>`, `archi-command:<line>` (runs it, returns `prompt`), `archi-material:<name>`
  (assigned to the element under the point), `archi-libblock:<file>␟<block>` ("Insert …", "Place …", "Assign Material").
- `file.drop {paths, x, y}` → `{open, scripts, unsupported, ids}`: drawings and scripts are returned for the shell to open /
  run; images, PDFs and exchange formats are imported at the drop point ("Drop <file>").
- `sheet.viewports {layout?}` → `{layout, index, paper, grid, viewports:[{index, rect, scale, ratioText, view, level, title,
  locked, clip?, modelWindow}]}`; `sheet.viewport {layout?, index, op: move {origin} | remove | lock | unlock | scale {ratio} |
  removeClip | clip {points} | center {center}}` ("Move Viewport", "Remove Viewport", "Lock Viewport" …; locked viewports refuse
  changes with -32000).
Portable commands with the Mac names: `VPLOCK`, `VPCLIP`, `VPMAX` (host `{"action":"maximizeViewport","layout","viewport","rect",
"level"}`), `VPMIN` (`{"action":"restoreViewport","layout","viewport"}`), `TOOLPALETTES` (`showPanel` Tools), `TOOLPALETTESCLOSE`
(`{"action":"hidePanel","panel":"Tools"}`), `RADIALMENU` (`{"action":"preference","key":"radialMenu","value"}`).
Fixtures: `canvas-*.json` (state, palette items, pick candidates, temporary dimensions, flips, chain, lasso, grips of a
polyline with its menu / previews / edit, placement, sheet viewports, a cursor sequence).

### 3D view (Host/EngineView3D.swift, EngineView3DCommands.swift)
The document data the Mac 3D viewport reads besides the meshes, the section caps, the gizmo commits and the portable
3D commands. Coordinates are model millimetres, Z up (the space of `model.meshes`).
- `view3d.info {}` → `{"cameras":[{"name":"Front","eye":[x,y,z],"target":[x,y,z],"fov":45,"orthographic":false},…],
  "currentCamera", "variables":{SECTIONBOX,SECTIONPLANE,PERSPECTIVE,RENDERPRESET,SUNSTUDY,WEATHER,OBJANIM,FOG…},
  "sectionBox":{on,min,max}|null, "sectionPlane":{on,point,normal}|null, "perspective":true, "visualStyle":"Shaded with Edges",
  "renderPreset":"Golden hour"|null, "materialMaps":{"CEDAR":{"normal":"textures/cedar_n.jpg","roughness":…,"normalStrength":1,
  "texture":"textures/cedar.jpg","textureScale":1200},…}, "water":[material names], "weather":{kind,intensity,season,snowCover,
  wetness,snow,fogDistance,particles:{birthRatePerM2,speed,size,life,stretch}|null}, "fog":{on,start,end,color,density},
  "animations":[OBJANIM entries + for doors "leafIndex" and "leaf":{hinge,sign,s0,s1,origin,dir,normal,wallHalf}],
  "northAngle", "units", "unitMM", "levels":[{id,name,elevation,height}] (by elevation), "currentLevel",
  "levelView":{isolate,explodeGap}, "gizmo":"Off|Move|Rotate|Scale", "measure":false, "site":{latitude,longitude,day,hour}}`.
  `visualStyle` is what the engine last asked the shell for (VSCURRENT, RENDER, RENDERPRESET) or `view3d.setVariable VSCURRENT`.
- `view3d.setVariable {name, value|null}` → `{name, value, changed}`: SECTIONBOX, SECTIONPLANE, PERSPECTIVE (0/1), SUNSTUDY
  ("day,hour"), RENDERPRESET, WEATHER, OBJANIM — validated, one undo step with the Mac control's label ("Section Box",
  "Clipping Plane", "Projection", "Sun Study" …); `VSCURRENT` only records the shell's visual style (not in the drawing).
- `view3d.setCamera {eye, target, fov?, orthographic?}` — the shell reports its camera (debounced) so SAVECAMERA, FOV and
  PANORAMA/STEREOPANORAMA `Camera` work in the engine.
- `view3d.saveCamera {name, eye?, target?, fov?, orthographic?}` / `view3d.deleteCamera {name}` → the saved cameras
  (undo "Save Camera" / "Delete Camera"; the camera menu's Save Current Camera… sheet and Delete submenu).
- `view3d.sectionCaps {point?, normal?}` (default the drawing's SECTIONPLANE when on) → `{"positions":base64 Float32 triangles,
  "triangleCount", "normal", "color":"#8c1f1a"}`: cut outlines of every mesh with the plane, triangulated (holes even-odd),
  0.5 mm inside the kept side (ArchiApp SectionCap / updateCaps).
- `view3d.transform {op, amount, axis?, pivot?, ids?}` → `{changed, message}`: the gizmo's commit on the selection (or `ids`):
  `move` (axis 0 = X, 1 = Y) and `movez` (axis 3: base/top offsets, sills, solids) in drawing units, `rotate` (radians about Z
  through `pivot`), `scale` (uniform in plan about `pivot`); undo labels "Move (3D gizmo)", "Move Z (3D gizmo)",
  "Rotate (3D gizmo)", "Scale (3D gizmo)" and the Mac messages ("Moved 1 object(s) by 250 along X.").
- `view3d.sun {day, hour}` → `{altitude, azimuth, direction, aboveHorizon, text}` (sun study at the site, NOAA calculator).
- `view3d.saveImage {path, data}` → `{path, bytes}`: writes base64 image data the shell rendered (panoramas, VIEWIMAGE,
  RENDERSAVE, ANIMATE Frame).
- `model.meshes` additions: each BIM mesh carries its `level`; `"binary": true` writes the buffers to a fresh temporary
  file (`archi-engine-<pid>-meshes-<n>.bin`, the previous one of the session is removed) and the result adds
  `"binary":path, "binaryLength", "layout":{"byteOrder":"little-endian","alignment":4,"units":…,"buffers":{…}}`. Full-detail
  Cedar House is one ~70 MB file instead of ~160 MB of base64 in the JSON line.

Portable 3D commands (same prompts, keywords and messages as the Mac) and their `host` actions
`{"action":"view3d","op":…}`: `GIZMO3D` → `gizmo {mode}`, `MEASURE3D` → `measure {on}`, `LEVELVIEW3D` → `levels {isolate,
explodeGap (mm)}`, `SECTIONBOX Panel` → `sectionBoxPanel` (On/Off/Selection/Level/Reset edit SECTIONBOX), `SECTIONPLANE`
(Horizontal/Vertical/Flip/Off edit SECTIONPLANE), `CLIPPLANES` → `clipPlanePanel`, `SUNSTUDY` → `sunStudy`, `ORBITSELECTION` → `orbitSelection {ids}`,
`SAVECAMERA` (engine), `CAMERA` → `camera {name, camera}`, `FOV` → `fov {fov}`, `FLY` / `LOOKAROUND` → `navigate {mode}`,
`POSITIONCAMERA` → `positionCamera {camera, mode:"look"}`, `TWOPOINT` → `twoPoint {on}` (the shell prints the lens shift),
`NAVSWHEEL` → `wheel {on}`, `WEATHER` / `SEASON` (engine, WEATHER variable), `MOVEZ` (engine), `ANIMATE` Door/Rotate/Move/
List/Delete/Clear (engine, OBJANIM) and Play/Stop → `animate {play}`, Frame → `animationFrame {time, path, samples}`,
`PANORAMA` / `STEREOPANORAMA` → `panorama {eye, width, stereo, ipd (mm), path|null, suggested}`, `VIEWIMAGE` →
`viewImage {width, height, format, transparent, path|null, suggested}`. Each also sends `show3D`.

### Output (Host/EngineOutput.swift, EngineOutputCommands.swift, EnginePlot.swift, EnginePDF.swift, EnginePathTracer.swift, EngineWebViewer.swift): plotting, publishing and rendering

The engine writes every PDF itself (Foundation only: plot style tables, lineweights, layers as optional content groups, bookmarks, Flate and DCT images), so the Windows shell only shows pages, prints SVG pages through Electron and encodes images/videos from the WebGL renderer.

Plotting:
- `plot.info {}` → `{what:[{value,title}], default, sheets:[{index,name,number,paper,style,placeholder,bookmark}], title, documentName, sheetNote, suggestedModel, suggestedAll}`. `value` is `"model"`, `"sheet:<i>"` or `"all"`; `default` is the active sheet (CTAB) or model.
- `plot.preview {what?|layout?, setup?, level?, svg?=true, svgFiles?=false}` → `{pdf, bytes, pageCount, pages:[{name,width,height,svg|svgPath}], title, ratio, status}`. `setup` overrides the page setup for this plot (same keys as `PAGESETUP` JSON: paper, orientation, area, scale, style, table, named, lineweightScale, stamp…). Pages are true-size (mm); viewports are clipped. Large drawings: pass `svgFiles:true` and read `svgPath` (the engine deletes the files on the next preview).
- `plot.pdf {path, what?|layout?, setup?, layered?=false, fromPreview?=false, quiet?}` → `{path, bytes, pages}`; `fromPreview` copies the file of the last preview. Each plot is added to the plot log.
- `plot.publish {path, layouts?=[all non-placeholder], bookmarks?=true, index?=false, quiet?}` → `{path, bytes, pages}` (multi-sheet PDF with outline).
- `plot.sheetSVG {path, all?|layout?}` → `{paths}` · `plot.shadePlotImage {layout, index, path}` (the shell's rendered image for a viewport with SHADEPLOT Rendered).
- `plotstyle.list {}` → `{tables:[{name,builtIn,pens:[{index,color,width,screen}]}], named}` · `plotstyle.save {table}` (stores a copy in the drawing) · `plotstyle.named {}` · `plotlog.get {limit?}` → `{rows}` · `plotlog.clear {}`.

Rendering:
- `render.window {}` → Render window state (presets from `render.presets`, output sizes, the look, sun, camera list, saved cameras). `render.queueName {name, folder?}` → a free file name for a queue job.
- `render.pass {pass, width, height, path?}` → data passes (depth, normal, object id, material id, AO) computed in the engine; `image` data URL when no `path`.
- `camerapath.list {}` · `camerapath.set {paths}` (CAMERAPATHS) · `camerapath.frames {path|label, fps, cameras?, seconds?}` → Catmull-Rom cameras per frame. `render.sunFrames {day, fromHour, toHour, fps, seconds}` → sun directions for a sun study.
- `pathtrace.start {width?, height?, samples?, camera?|cameraName?, environment?, day?, hour?, clay?, ground?, lod?, mix?, denoise?, ev?, sync?}` → `{triangles, lights, textures, width, height, target, status}`; runs on a background thread. `pathtrace.status {image?=true, mix?, denoise?, ev?}` → `{running, samples, target, seconds, status, image}` · `pathtrace.stop` · `pathtrace.save {path}` · `pathtrace.mix {sun, sky, artificial}` (light mixer without re-rendering).
- `webviewer.export {path}` → a stand-alone HTML 3D viewer of the model (WEBVIEWEREXPORT).

Commands and `host` notifications: PLOT sends `{action:"plot"}` (the shell opens the print dialog; `PLOT <file>` writes the PDF in the engine). PREVIEW, PRINTSETUP, BATCHPUBLISH, PLOTSTYLE, RENDERQUEUE, CAMERAPATHEDIT and PATHTRACE send `{action:"dialog", dialog:"plotPreview"|"printSetup"|"batchPublish"|"plotStyles"|"renderQueue"|"cameraPaths"|"pathTrace"}`; RENDER sends `{action:"render"}` (Render window). Operations the engine cannot finish alone send `{action:"output", op:…}`: `publish` (PUBLISH without a file name), `sheetSVG`, `openFile`, `lightMix`, `renderSave` (RENDERSAVE), `renderToFile` (RENDERTOFILE: the shell renders beauty with WebGL, the engine writes data passes), `video` (WALKTHROUGHVIDEO / SUNSTUDYVIDEO / turntable: MP4 via WebCodecs in the shell) and `shadePlotRender`. PLOTSTYLENAME, PLOTAREA, SHADEPLOT, PLOTLOG and EXPORTPDF finish in the engine. `file.export {format:"pdf"}` plots the active sheet or the model.

Fixtures: `output-plot-info`, `output-preview-sheet` (Cedar House A-102), `output-preview-model`, `output-plotstyle-list`, `output-command-preview`, `output-render-window`, `output-camerapath-list`, `output-camerapath-frames`, `output-sun-frames`, `output-command-renderqueue`, `output-command-rendersave`.

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
`command-complete`, `error-unknown-method`, the 3D view exchanges `view3d-info`, `view3d-info-animated` (door leaves),
`view3d-setvariable`, `view3d-caps`, `view3d-camera`, `view3d-sun`, `view3d-transform`, `view3d-meshes-binary` (path and
layout only), and `index.json`.

## Not in the engine (the shell or the Mac UI layer does it)

Commands the Mac defines in its UI layer (ArchiApp: views, dialogs, render window, plotting through Core Graphics,
scripting console) are not in the engine's registry; `RENDERPRESET` and the tool-window commands above have portable
versions registered by archi-engine. The script console's `archi` API runs in the shell's JavaScript and calls this protocol.
