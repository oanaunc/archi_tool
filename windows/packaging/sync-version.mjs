// Oanarina Archi Tool — GPL-3.0-or-later
// Keeps the Windows version equal to the Mac app's: reads CFBundleShortVersionString (and CFBundleVersion, the build
// number) from app/Info.plist and writes windows/package.json "version" (x.y.z). Prints "version=<x.y.z>" and
// "build=<x.y.z.n>" for $GITHUB_OUTPUT; electron-builder uses the version for the installer name, the uninstall entry
// and the .exe product version, and -c.buildVersion=<build> for the file version.
// Usage: node packaging/sync-version.mjs [--check]   (--check: exit 1 when package.json differs, write nothing)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const windows = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const plist = fs.readFileSync(path.resolve(windows, "../app/Info.plist"), "utf8");
const key = (k) => plist.match(new RegExp(`<key>${k}</key>\\s*<string>([^<]*)</string>`))?.[1]?.trim();
const short = key("CFBundleShortVersionString");
if (!short || !/^\d+(\.\d+){0,2}$/.test(short)) { console.error(`sync-version: no usable CFBundleShortVersionString in app/Info.plist (${short})`); process.exit(1); }
const parts = short.split(".").map(Number);
while (parts.length < 3) parts.push(0);
const version = parts.join(".");
const buildNo = Number.parseInt(key("CFBundleVersion") ?? "0", 10) || 0;
const pkgPath = path.join(windows, "package.json");
const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
if (process.argv.includes("--check")) {
  if (pkg.version !== version) { console.error(`sync-version: windows/package.json ${pkg.version} ≠ app/Info.plist ${version}`); process.exit(1); }
} else if (pkg.version !== version) {
  pkg.version = version;
  fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + "\n");
}
console.log(`version=${version}`);
console.log(`build=${version}.${buildNo}`);
