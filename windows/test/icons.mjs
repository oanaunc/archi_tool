// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Icon coverage: every SF Symbol the shell uses (ribbon/menus/panels/palettes data and literal icon("…") calls in src/)
// has an explicit Lucide mapping in tools/sf-to-lucide.mjs and a generated glyph in src/renderer/data/icons.generated.json,
// so no button falls back to the generic terminal glyph. Run: node test/icons.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { explicit } from "../tools/sf-to-lucide.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const data = path.join(root, "src/renderer/data");
const { icons } = JSON.parse(fs.readFileSync(path.join(data, "icons.generated.json"), "utf8"));
const used = new Map();
const note = (sf, where) => { if (!used.has(sf)) used.set(sf, where); };
for (const f of fs.readdirSync(data).filter((f) => f.endsWith(".json") && !f.startsWith("icons") && f !== "ribbon-fallback.json")) {
  (function walk(o) {
    if (Array.isArray(o)) o.forEach(walk);
    else if (o && typeof o === "object") { if (typeof o.symbol === "string" && o.symbol) note(o.symbol, f); Object.values(o).forEach(walk); }
  })(JSON.parse(fs.readFileSync(path.join(data, f), "utf8")));
}
(function scan(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) scan(p);
    else if (e.name.endsWith(".ts")) for (const m of fs.readFileSync(p, "utf8").matchAll(/\bicon\(\s*["'`]([a-z0-9]+(?:\.[a-z0-9]+)*)["'`]/g)) note(m[1], path.relative(root, p));
  }
})(path.join(root, "src"));

const terminal = JSON.stringify(icons["terminal"]?.nodes);
const problems = [];
for (const [sf, where] of [...used].sort()) {
  if (!explicit[sf]) problems.push(`${sf} (${where}): no entry in tools/sf-to-lucide.mjs`);
  else if (!icons[sf]) problems.push(`${sf} (${where}): not in icons.generated.json (run npm run gen)`);
  else if (icons[sf].lucide !== explicit[sf]) problems.push(`${sf}: generated as ${icons[sf].lucide}, mapped to ${explicit[sf]} (run npm run gen)`);
  else if (explicit[sf] !== "SquareTerminal" && JSON.stringify(icons[sf].nodes) === terminal) problems.push(`${sf}: fell back to the terminal glyph (${explicit[sf]} not found)`);
}
console.log(`icons: ${used.size} SF Symbols used, ${Object.keys(icons).length} generated, ${problems.length} problems`);
for (const p of problems) console.log("  FAIL " + p);
if (problems.length) process.exit(1);
console.log("PASS icons");
