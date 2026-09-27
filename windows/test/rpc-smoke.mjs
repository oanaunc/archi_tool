// JSON-RPC client smoke test: runs src/main/rpc.ts (bundled) against a stand-in engine that answers from
// test/fixtures/engine (and against a real archi-engine when ARCHI_ENGINE is set). Usage: node test/rpc-smoke.mjs
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const require = createRequire(import.meta.url);
let esbuild; try { esbuild = require("esbuild"); } catch { esbuild = require(process.env.ESBUILD_PATH); }
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "rpc-"));
await esbuild.build({ entryPoints: [path.join(root, "src/main/rpc.ts")], bundle: true, platform: "node", format: "cjs", outfile: path.join(tmp, "rpc.js"), logLevel: "error" });
const { EngineProcess } = require(path.join(tmp, "rpc.js"));
const fx = path.join(root, "test/fixtures/engine");
const stub = path.join(tmp, "engine.mjs");
fs.writeFileSync(stub, `
import fs from "node:fs"; import readline from "node:readline";
const recs = []; for (const f of JSON.parse(fs.readFileSync(${JSON.stringify(fx)} + "/index.json"))) { const p = ${JSON.stringify(fx)} + "/" + f; if (!fs.existsSync(p)) continue; const j = JSON.parse(fs.readFileSync(p)); for (const r of Array.isArray(j) ? j : [j]) recs.push(r); }
const out = (o) => process.stdout.write(JSON.stringify(o) + "\\n");
out({ jsonrpc: "2.0", method: "ready", params: { version: "stub", protocol: "1.0" } });
readline.createInterface({ input: process.stdin }).on("line", (l) => {
  const m = JSON.parse(l); const r = recs.find((x) => x.request.method === m.method);
  if (!r) { out({ jsonrpc: "2.0", id: m.id, error: { code: -32601, message: "Method not found: " + m.method } }); return; }
  for (const n of r.notifications ?? []) out(n);
  out({ jsonrpc: "2.0", id: m.id, ...(r.response.error ? { error: r.response.error } : { result: r.response.result }) });
});`);
const exe = process.env.ARCHI_ENGINE ?? process.execPath;
const e = new EngineProcess(exe, process.env.ARCHI_ENGINE ? [] : [stub]);
const notes = []; e.on("notification", (n) => notes.push(n.method));
e.start();
const ok = (c, m) => { console.log(`${c ? "PASS" : "FAIL"}  ${m}`); if (!c) process.exitCode = 1; };
const hello = await e.call("engine.hello");
ok(hello.commands.length > 500, `engine.hello: ${hello.commands.length} commands`);
const info = await e.call("doc.open", { path: path.join(root, "../assets/demo/Cedar House.archi") });
ok(info.title === "Cedar House", `doc.open: ${info.title}, ${info.entities} objects`);
const dl = await e.call("view.drawList", { rect: info.extents, pixelsPerUnit: 0.05 });
ok(dl.items.length > 500, `view.drawList: ${dl.items.length} items`);
const st = await e.call("command.run", { line: "LINE" });
ok(st.active && st.command === "LINE", `command.run LINE: ${st.message}`);
try { await e.call("no.such.method"); ok(false, "error expected"); } catch (err) { ok(err.code === -32601, `error: ${err.message}`); }
ok(notes.includes("ready") || notes.includes("log"), `notifications: ${[...new Set(notes)].join(", ")}`);
e.stop();
setTimeout(() => process.exit(process.exitCode ?? 0), 300);
