// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Start-screen plan thumbnail of a bundled sample (resources/assets/samples/<name>.thumb.json, painted by
// src/renderer/canvas/thumbnail.ts): the engine's view.drawList of the sample's current level, without text and ids.
// Usage: node tools/sample-thumb.mjs <engine output .jsonl> <response id> "resources/assets/samples/<name>.thumb.json"
//   e.g. replay {"id":9101,"method":"doc.open","params":{"path":"assets/demo/Nordic House.archi"}} and
//        {"id":9102,"method":"view.drawList","params":{}} through archi-engine, then pass the output and 9102.
import fs from "node:fs";
const [src, id, out] = process.argv.slice(2);
if (!src || !id || !out) { console.error("usage: node tools/sample-thumb.mjs <engine output .jsonl> <response id> <out .thumb.json>"); process.exit(2); }
let result = null;
for (const line of fs.readFileSync(src, "utf8").split("\n")) {
  if (!line.includes(`"id":${id}`) && !line.includes(`"id": ${id}`)) continue;
  const r = JSON.parse(line);
  if (String(r.id) === String(id)) { result = r.result; break; }
}
if (!result?.items?.length) { console.error(`no view.drawList result with id ${id} in ${src}`); process.exit(1); }
const items = result.items.filter((i) => i.type !== "text").map(({ id: _id, ...rest }) => rest);
fs.writeFileSync(out, JSON.stringify({ items }));
console.log(`${out}: ${items.length} items (bounds ${JSON.stringify(result.bounds)})`);
