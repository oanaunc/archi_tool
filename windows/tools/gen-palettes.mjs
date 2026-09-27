// Generates src/renderer/data/palettes.generated.json — the Mac tool palettes (ToolPalette.swift: Draw, Modify,
// Annotate, Build, Blocks, Components, My Tools) from ../docs/windows-parity.json. Run by gen-ui-data.mjs users or directly.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const parity = path.resolve(root, "../docs/windows-parity.json");
const out = path.join(root, "src/renderer/data/palettes.generated.json");
if (!fs.existsSync(parity)) { console.log("palettes: docs/windows-parity.json not found, kept", path.relative(root, out)); process.exit(0); }
const p = JSON.parse(fs.readFileSync(parity, "utf8"));
const palettes = (p.palettes ?? []).map((x) => ({
  name: x.name, kind: x.kind ?? "commands",
  ...(x.items ? { items: x.items.map((i) => ({ title: i.title, symbol: i.symbol, command: i.command, ...(i.names ? { names: i.names } : {}), ...(i.args ? { args: i.args } : {}) })) } : {}),
  ...(x.default ? { default: x.default } : {}),
}));
fs.writeFileSync(out, JSON.stringify({ source: "docs/windows-parity.json palettes (ToolPalette.swift)", palettes }, null, 1) + "\n");
console.log(`palettes: ${palettes.length} palettes → ${path.relative(root, out)}`);
