// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The offline help browser (HELPWINDOW / DOCS / HELPBROWSER / MANUAL; HelpPages + HelpBrowser in AppNavigationViews.swift):
// the same pages as the Mac — the command index with a filter, one page per command (aliases, category, where it is in
// the menus and ribbon, whether it changes the drawing, how to run it from the command line / scripts / agents, a Run
// link, related commands), the tutorials with Run links, keyboard and mouse, scripting and the archi API — plus the user
// guide (docs/USER-GUIDE.md, bundled into the app, rendered offline). Links: archi-help:<route> opens a page, archi-run:
// <line> runs a command line in this drawing, https:// opens the browser. One window, 820 × 640, "Oanarina Archi Tool Help".
import type { App } from "../app";
import { h } from "../dom";
import { toolWindow, type WindowHandle } from "../dialogs/ui";
import { commandLocations } from "../ui/help";
import { API } from "../partb/script-data";
import ui from "../data/ui.generated.json";
import guideMarkdown from "../../../../docs/USER-GUIDE.md";
import { esc, renderMarkdown } from "./markdown";

interface Cmd { name: string; aliases: string[]; category: string; summary: string; modifies?: boolean }

/** Bundled tutorials (HelpPages.tutorials): each step names a command line that the "Run" link executes. */
export const TUTORIALS: { title: string; intro: string; steps: [string, string][] }[] = [
  { title: "1 · Your first floor plan", intro: "Draw four walls, add a door and a window, tag the room and dimension the walls.", steps: [
    ["Start a new metric drawing.", "NEW"], ["Draw a 6 × 4 m rectangle of walls: click four corners, then C to close.", "WALL"],
    ["Place a door in a wall.", "DOOR"], ["Place a window.", "WINDOW"], ["Click inside the walls to create the room.", "ROOM"],
    ["Dimension all walls automatically.", "AUTODIMWALLS"], ["Zoom to everything.", "ZOOM E"]] },
  { title: "2 · Sheets and PDF", intro: "Put the plan on an A3 sheet at 1:100 and export a vector PDF.", steps: [
    ["Create a sheet.", "LAYOUT"], ["Add a viewport of the plan.", "MVIEW"], ["Fill in the title block.", "TITLEBLOCK"],
    ["Preview the plot.", "PREVIEW"], ["Publish all sheets to one PDF.", "PUBLISH"]] },
  { title: "3 · 3D, styles and rendering", intro: "Look at the model in 3D, change the visual style and render an image.", steps: [
    ["Show the 3D view.", "SHOW3D"], ["South-west isometric view.", "ISOVIEW"], ["Hidden-line style.", "VSCURRENT Hidden"],
    ["Shaded with edges.", "VSCURRENT shadedwithEdges"], ["Render the view.", "RENDER"]] },
  { title: "4 · The sample house", intro: "Open the bundled sample project: a two-storey house with levels, sheets and rooms.", steps: [
    ["Open the sample house in a new window.", "SAMPLEHOUSE"], ["Browse its sheets with the tabs under the canvas.", "LAYOUTTABS"]] },
];

/** AutoCAD-compatible function keys (FunctionKeys.table). */
export const FUNCTION_KEYS: [string, string][] = [
  ["F1", "Help (the running command's page)"], ["F2", "Command history panel"], ["F3", "Object snap on/off"],
  ["F7", "Grid display"], ["F8", "Ortho mode"], ["F9", "Grid snap"], ["F10", "Polar tracking"],
  ["F11", "Object snap tracking"], ["F12", "Dynamic input"],
];

export const runLink = (line: string) => "archi-run:" + encodeURIComponent(line);

const STYLE = `<style>
:host{all:initial}
.page{font:13px "Segoe UI",system-ui,sans-serif;background:#1e1f22;color:#e6e6e6;margin:0;padding:18px 26px;line-height:1.45;min-height:100%;box-sizing:border-box;-webkit-user-select:text;user-select:text}
a{color:#F5C518;text-decoration:none;cursor:pointer}a:hover{text-decoration:underline}h1{font-size:20px}h2{font-size:15px;margin-top:22px;border-bottom:1px solid #333;padding-bottom:4px}
h3{font-size:13px;margin-top:18px}code{background:#2b2c31;padding:1px 5px;border-radius:3px;font-family:Consolas,"Cascadia Mono",monospace}nav a{margin-right:14px}table{border-collapse:collapse}td,th{padding:3px 10px 3px 0;vertical-align:top;text-align:left}
.dim{color:#9a9ba1}.run{background:#F5C518;color:#1e1f22;padding:1px 7px;border-radius:3px;font-size:11px}input{background:#2b2c31;color:#eee;border:1px solid #444;padding:5px;width:320px;border-radius:4px;font:inherit}
pre{background:#2b2c31;padding:8px 10px;border-radius:4px;overflow:auto}pre code{background:none;padding:0}.guide table{margin:6px 0}.guide th{color:#9a9ba1;font-weight:600;border-bottom:1px solid #333}
</style>`;

function page(body: string): string {
  return `${STYLE}<div class="page"><nav><a href="archi-help:index">Commands</a><a href="archi-help:tutorials">Tutorials</a><a href="archi-help:shortcuts">Keyboard &amp; mouse</a><a href="archi-help:scripting">Scripting</a><a href="archi-help:guide">User guide</a></nav>${body}</div>`;
}

const sorted = (cmds: Cmd[]) => [...cmds].sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
const lookup = (cmds: Cmd[], n: string) => { const u = n.toUpperCase(); return cmds.find((c) => c.name === u) ?? cmds.find((c) => (c.aliases ?? []).includes(u)); };

export function indexPage(cmds: Cmd[]): string {
  const list = sorted(cmds);
  let b = `<h1>Oanarina Archi Tool help</h1><p class=dim>${list.length} commands. Type a command name on the command line, or press F1 while a command runs to open its page.</p>`;
  b += `<input id=q placeholder='Filter commands…'>`;
  const groups = new Map<string, Cmd[]>();
  for (const c of list) { const g = groups.get(c.category) ?? []; g.push(c); groups.set(c.category, g); }
  for (const cat of [...groups.keys()].sort()) {
    b += `<h2>${esc(cat)}</h2><table>`;
    for (const d of groups.get(cat)!) b += `<tr class=c><td><a href="archi-help:cmd/${d.name}"><code>${d.name}</code></a></td><td class=dim>${esc((d.aliases ?? []).join(", "))}</td><td>${esc(d.summary)}</td></tr>`;
    b += "</table>";
  }
  return page(b);
}

export function commandPage(cmds: Cmd[], name: string): string | null {
  const d = lookup(cmds, name);
  if (!d) return null;
  const where = commandLocations().get(d.name) ?? "Command line";
  const aliases = d.aliases ?? [];
  let b = `<h1><code>${d.name}</code></h1><p>${esc(d.summary)}</p><table>`;
  b += `<tr><td class=dim>Aliases</td><td>${aliases.length ? esc(aliases.join(", ")) : "—"}</td></tr>`;
  b += `<tr><td class=dim>Category</td><td>${esc(d.category)}</td></tr>`;
  b += `<tr><td class=dim>Where</td><td>${esc(where)}</td></tr>`;
  b += `<tr><td class=dim>Changes the drawing</td><td>${d.modifies ? "Yes — one undo step" : "No"}</td></tr></table>`;
  b += `<h2>Use it</h2><p>Command line: <code>${d.name}</code>${aliases[0] ? ` or <code>${esc(aliases[0])}</code>` : ""} · Script: <code>archi.run("${d.name} ")</code> · Agent: <code>run_command {"command":"${d.name}"}</code></p>`;
  b += `<p><a class=run href="${runLink(d.name)}">Run ${d.name}</a></p>`;
  b += `<h2>Input</h2><p class=dim>Points: <code>x,y</code> · <code>@dx,dy</code> · <code>@dist&lt;angle</code> · a bare number = distance along the cursor. Options: type the capital letters of a keyword. Esc cancels, Enter accepts the default.</p>`;
  const anchor = ((ui as any).guide?.commands ?? {})[d.name] ?? ((ui as any).guide?.categories ?? {})[d.category];
  if (anchor) b += `<p><a href="archi-help:guide#${anchor}">User guide: ${esc(d.category)}</a></p>`;
  const related = sorted(cmds).filter((c) => c.category === d.category && c.name !== d.name).slice(0, 12);
  if (related.length) b += `<h2>Related</h2><p>${related.map((c) => `<a href="archi-help:cmd/${c.name}">${c.name}</a>`).join(" · ")}</p>`;
  return page(b);
}

export function tutorialsPage(): string {
  let b = "<h1>Tutorials and sample project</h1>";
  for (const t of TUTORIALS) {
    b += `<h2>${esc(t.title)}</h2><p>${esc(t.intro)}</p><ol>`;
    for (const [text, line] of t.steps) b += `<li>${esc(text)} <code>${esc(line)}</code> <a class=run href="${runLink(line)}">Run</a></li>`;
    b += "</ol>";
  }
  return page(b);
}

export function shortcutsPage(): string {
  let b = "<h1>Keyboard and mouse</h1><h2>Function keys (AutoCAD compatible)</h2><table>";
  for (const [k, a] of FUNCTION_KEYS) b += `<tr><td><code>${k}</code></td><td>${esc(a)}</td></tr>`;
  b += "</table><h2>Grips</h2><table><tr><td>Click a grip</td><td>Stretch; Space cycles Move, Rotate, Scale, Mirror; type a distance or MO/RO/SC/MI/ST; C = copy</td></tr>";
  b += "<tr><td>Right-click a grip</td><td>Add / remove vertex, convert to arc or line, lengthen, radius</td></tr><tr><td>Space while dragging</td><td>Rotate 90° about the grip</td></tr></table>";
  b += "<h2>Selection</h2><table><tr><td>Drag left → right</td><td>Window selection</td></tr><tr><td>Drag right → left</td><td>Crossing selection</td></tr><tr><td>Alt-drag</td><td>Lasso (clockwise = window, counter-clockwise = crossing)</td></tr><tr><td>Tab over a wall</td><td>Select the chain of joined walls</td></tr><tr><td>Right-click</td><td>Shortcut menu (Repeat, Recent Input, Move, Copy, Rotate, Erase, Properties)</td></tr></table>";
  b += "<h2>View</h2><table><tr><td>Scroll / pinch</td><td>Zoom about the cursor</td></tr><tr><td>Middle-drag, Space-drag, two-finger scroll</td><td>Pan</td></tr><tr><td>Double middle-click</td><td>Zoom extents</td></tr><tr><td><code>DVIEW TW</code></td><td>Twist (rotate) the plan display</td></tr></table>";
  return page(b);
}

export function scriptingPage(): string {
  let b = `<h1>Scripting and agents</h1><h2>JavaScript console (Ctrl+Alt+J)</h2><p><code>archi.run("LINE 0,0 1000,0 ")</code> runs any command; <code>archi.entities()</code>, <code>archi.add({...})</code>, <code>archi.select([ids])</code>, <code>archi.doc()</code> read and edit the drawing.</p>`;
  b += `<h2>Agent server</h2><p>JSON-RPC 2.0 over HTTP on <code>127.0.0.1:47800</code> with a per-session token (Settings ▸ Agents). Methods: <code>run_command</code>, <code>get_document</code>, <code>list_entities</code>, <code>add_entity</code>, <code>update_entity</code>, <code>delete_entities</code>, <code>add_element</code>, <code>export</code>, <code>screenshot</code>, <code>list_methods</code>.</p>`;
  b += `<h2>Command scripts</h2><p><code>SCRIPT</code> runs a .scr file: one command line per line, exactly as typed.</p><h2>archi API reference</h2><table>`;
  b += API.map(([sig, doc, ex]) => `<tr><td><code>${esc(sig)}</code></td><td>${esc(doc)}<br><code class=dim>${esc(ex)}</code></td></tr>`).join("");
  return page(b + "</table>");
}

let guideHTML: string | null = null;
export function guidePage(): string {
  guideHTML ??= renderMarkdown(String(guideMarkdown));
  return page(`<div class="guide">${guideHTML}</div>`);
}

/** HTML for a route: "index", "cmd/NAME", "tutorials", "shortcuts", "scripting", "guide" (HelpPages.html). */
export function helpHtml(cmds: Cmd[], route: string): string {
  if (route.startsWith("cmd/")) return commandPage(cmds, route.slice(4)) ?? indexPage(cmds);
  switch (route.split("#")[0]) {
    case "tutorials": return tutorialsPage();
    case "shortcuts": return shortcutsPage();
    case "scripting": return scriptingPage();
    case "guide": return guidePage();
    default: return indexPage(cmds);
  }
}

/** Help topic for F1 (HelpPages.contextRoute): the running command, else the command typed so far, else the index. */
export function contextRoute(app: App): string {
  if (app.prompt?.active && app.prompt.command) { const d = app.lookup(String(app.prompt.command)); if (d) return "cmd/" + d.name; }
  const typed = (app.commandInput ?? "").trim().split(/\s+/)[0] ?? "";
  const d = typed ? app.lookup(typed) : undefined;
  return d ? "cmd/" + d.name : "index";
}

// ---- the window ----
let win: WindowHandle | null = null;
let shadow: ShadowRoot | null = null;
export let currentRoute = "index";

export function showHelpBrowser(app: App, route = "index") {
  currentRoute = route;
  if (!win || !win.el.isConnected) {
    win = toolWindow("help-browser", "Oanarina Archi Tool Help", 820, 640, (body) => {
      const host = h("div", { class: "help-browser" });
      host.style.cssText = "height:100%;overflow:auto;background:#1e1f22";
      shadow = host.attachShadow({ mode: "open" });
      shadow.addEventListener("click", (e) => {
        const a = (e.target as HTMLElement).closest?.("a") as HTMLAnchorElement | null;
        const href = a?.getAttribute("href");
        if (!href) return;
        e.preventDefault();
        if (href.startsWith("archi-help:")) showHelpBrowser(app, href.slice("archi-help:".length));
        else if (href.startsWith("archi-run:")) void app.runCommand(decodeURIComponent(href.slice("archi-run:".length)));
        else if (/^https:\/\//.test(href)) void app.action(`@openURL:${href}`);
        else if (href.startsWith("#")) scrollTo(href.slice(1));
      });
      body.append(host);
    }, () => { win = null; shadow = null; });
  }
  render(app);
  win.focus();
  return win;
}

function scrollTo(id: string) {
  const t = id ? (shadow?.getElementById(id) as HTMLElement | null) : null;
  const host = shadow?.host as HTMLElement | undefined;
  if (!host) return;
  if (t) host.scrollTop = t.offsetTop - 8; else host.scrollTop = 0;
}

function render(app: App) {
  if (!shadow) return;
  const cmds = (app.hello?.commands ?? []) as Cmd[];
  shadow.innerHTML = helpHtml(cmds, currentRoute);
  (shadow.host as HTMLElement).dataset.route = currentRoute;
  const q = shadow.getElementById("q") as HTMLInputElement | null;
  q?.addEventListener("input", () => {
    const v = q.value.toLowerCase();
    shadow!.querySelectorAll<HTMLElement>("tr.c").forEach((e) => { e.style.display = (e.textContent ?? "").toLowerCase().includes(v) ? "" : "none"; });
  });
  const hash = currentRoute.includes("#") ? currentRoute.slice(currentRoute.indexOf("#") + 1) : "";
  requestAnimationFrame(() => scrollTo(hash));
}
