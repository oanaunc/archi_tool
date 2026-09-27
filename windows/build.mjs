// Bundles the Electron main process, the preload script and the renderer with esbuild into dist/.
// `node build.mjs --web` also copies the test fixtures next to the renderer so dist/renderer/index.html runs in a browser.
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
let esbuild;
try { esbuild = require("esbuild"); } catch { esbuild = require(process.env.ESBUILD_PATH || "esbuild"); }
const dist = path.join(root, "dist");
fs.rmSync(dist, { recursive: true, force: true });
const common = { bundle: true, sourcemap: true, logLevel: "warning", target: "es2022" };

await esbuild.build({ ...common, entryPoints: ["src/main/main.ts"], outfile: "dist/main/main.js", platform: "node", format: "cjs", external: ["electron"] });
await esbuild.build({ ...common, entryPoints: ["src/preload/preload.ts"], outfile: "dist/preload/preload.js", platform: "node", format: "cjs", external: ["electron"] });
await esbuild.build({ ...common, entryPoints: ["src/renderer/main.ts"], outfile: "dist/renderer/renderer.js", platform: "browser", format: "iife", loader: { ".json": "json" } });

const copy = (from, to) => { if (fs.existsSync(from)) fs.cpSync(from, to, { recursive: true }); };
copy(path.join(root, "src/renderer/index.html"), path.join(dist, "renderer/index.html"));
copy(path.join(root, "resources/assets"), path.join(dist, "renderer/assets"));
if (process.argv.includes("--web")) copy(path.join(root, "test/fixtures"), path.join(dist, "renderer/fixtures"));
console.log("built dist/ (main, preload, renderer)");
