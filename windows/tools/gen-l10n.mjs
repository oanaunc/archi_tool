// Generates src/renderer/data/l10n.generated.json from the Mac app's ribbon and menu translations
// (app/Sources/ArchiApp/Localization.swift L10n.table and LocalizationMenus.swift L10n.menuTable): English → [ro, de, fr, es, it].
// Without the Mac sources (a windows/-only checkout) the committed JSON is kept.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const src = path.resolve(root, "../../app/Sources/ArchiApp");
const out = path.resolve(root, "../src/renderer/data/l10n.generated.json");
const files = ["Localization.swift", "LocalizationMenus.swift"].map((f) => path.join(src, f));
if (!files.every((f) => fs.existsSync(f))) { console.log("l10n: Mac sources not found, keeping", path.relative(process.cwd(), out)); process.exit(0); }
const unq = (s) => JSON.parse(`"${s}"`);
const table = {};
const menus = {};
const row = /^\s*"((?:[^"\\]|\\.)*)"\s*:\s*\[((?:\s*"(?:[^"\\]|\\.)*"\s*,?)+)\]\s*,?\s*$/;
for (const [i, f] of files.entries()) {
  const target = i === 0 ? table : menus;
  for (const line of fs.readFileSync(f, "utf8").split("\n")) {
    const m = row.exec(line);
    if (!m) continue;
    const vals = [...m[2].matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((x) => unq(x[1]));
    if (vals.length === 5) target[unq(m[1])] = vals;
  }
}
const data = { languages: [["en", "English"], ["ro", "Română"], ["de", "Deutsch"], ["fr", "Français"], ["es", "Español"], ["it", "Italiano"]], order: ["ro", "de", "fr", "es", "it"], table, menuTable: menus };
fs.writeFileSync(out, JSON.stringify(data, null, 0) + "\n");
console.log(`l10n: ${Object.keys(table).length} ribbon + ${Object.keys(menus).length} menu strings → ${path.relative(process.cwd(), out)}`);
