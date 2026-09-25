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
| `run_command` | `command` | AutoCAD-style command line(s); returns the log |
| `get_document_summary` | – | overview: units, layers, levels, counts, bounds, unsaved changes |
| `get_document` | – | whole document JSON |
| `list_entities` | `type?`, `layer?`, `limit?` | drafting entities |
| `list_elements` | `type?`, `level?` | BIM elements |
| `add_entity` | `entity` | add entities (object or array) |
| `add_element` | `element` | add BIM elements |
| `update_entity` | `id`, `patch` | modify an entity/element |
| `delete` | `ids` | delete |
| `save` | `path?` | save as `.archi` (default: the opened file) |
| `export` | `path`, `format?`, `level?` | dxf, svg, ifc, obj, stl, glb, csv, archi |
| `list_commands` | `category?` | available commands |
| `undo` | – | undo last change |

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
```

Script files contain one command line per line; lines starting with `;` are comments.
