// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Agents (AgentSettings.swift): the local agent server box (status, port, start/stop, auto-start, token, info file),
// "Connect Claude" help (archi-engine --mcp for Claude Desktop / Claude Code, and the HTTP agent server of this window),
// the ribbon's AI Agents group state and the agent `screenshot` method (the 2D plan as PNG).
import type { App } from "../app";
import { h, clear, button, iconButton, field, toggleSwitch, header, spacer, Sheet, ToolWindow, ico, row } from "./ui";
import * as N from "./native";
import { paintFitted } from "./plan-paint";

export async function toggleAgentServer(app: App) {
  const s = await N.agentStatus();
  if (!N.isElectron()) { app.print("The agent server runs in the Windows app."); return; }
  if (s.running) { await N.agentStop(); app.print("Agent server stopped."); return; }
  const r = await N.agentStart();
  await new Promise((res) => setTimeout(res, 150));
  const now = await N.agentStatus();
  if (r.ok && now.running) app.print(`Agent server listening on 127.0.0.1:${now.port}`);
  else app.print(`Agent server could not start: ${r.error ?? now.error ?? "unknown error"}`);
}

/** LOCAL AGENT SERVER + CONNECT CLAUDE (Settings ▸ Agents). Also used by the Settings dialog's Agents page. */
export function agentPrefsView(app: App): HTMLElement {
  const el = h("div", { class: "pb-col", style: { gap: "14px" } });
  let reveal = false, status = "";
  const render = () => {
    const s = N.agentLast();
    clear(el);
    const dot = h("span", { style: { width: "8px", height: "8px", borderRadius: "50%", background: s.running ? "#34C759" : "var(--faint)", display: "inline-block" } });
    const port = field({ value: String(s.prefPort || 47800), width: 70, onCommit: (v) => { const n = Math.round(Number(v)); if (isFinite(n)) N.agentPrefs({ port: Math.max(1024, Math.min(n, 65535)) }); } });
    const token = h("span", { class: "pb-mono", style: { flex: "1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", userSelect: "text" }, text: reveal ? s.token : "•".repeat(24) });
    const info = (s.infoFile || "").replace(/^.*?(\\AppData\\Roaming|\/AppData\/Roaming)/i, "%APPDATA%");
    el.append(
      h("div", { class: "pb-col", style: { gap: "8px" } }, header("Local Agent Server"),
        h("div", { class: "pb-box pb-col", style: { gap: "9px" } },
          row(dot, h("span", { style: { fontWeight: "600" }, text: s.running ? `Listening on http://127.0.0.1:${s.port}/rpc` : "Stopped" }), spacer(),
            button(s.running ? "Stop" : "Start", { prominent: !s.running, onClick: async () => {
              if (s.running) { await N.agentStop(); status = "Server stopped."; }
              else { const r = await N.agentStart(Number(port.value) || s.prefPort); status = r.ok ? `Server started for “${app.info?.title ?? "Untitled"}”.` : `Could not start: ${r.error}`; }
              render();
            } })),
          row(h("span", { text: "Port" }), port, h("span", { class: "pb-small pb-dim", text: "(127.0.0.1 only; restart the server to apply)" })),
          toggleSwitch("Start the agent server when the app launches", s.autoStart, (v) => N.agentPrefs({ autoStart: v })),
          row(h("span", { style: { width: "40px" }, text: "Token" }), token,
            iconButton(reveal ? "eye.slash" : "eye", reveal ? "Hide" : "Reveal", () => { reveal = !reveal; render(); }),
            button("Copy Token", { compact: true, onClick: async () => { await N.copy(s.token); status = "Token copied. Send it as “Authorization: Bearer <token>”."; render(); } })),
          row(h("span", { style: { width: "60px" }, text: "Info file" }), h("span", { class: "pb-mono pb-dim", style: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }, text: info })),
          h("div", { class: "pb-small pb-dim", text: "The token changes every launch. Agents can also read the port and token from the info file while the server runs." }),
          status ? h("div", { class: "pb-small pb-accent", text: status }) : null,
          s.error ? h("div", { class: "pb-small pb-danger", text: s.error }) : null)),
      h("div", { class: "pb-col", style: { gap: "8px" } }, header("Connect Claude"),
        h("div", { class: "pb-box pb-col", style: { gap: "8px" } },
          h("div", { text: "Claude Desktop and Claude Code talk to Oanarina Archi Tool through the bundled archi-engine in MCP mode, or to this running window through the local agent server." }),
          row(button("Show Setup Instructions…", { prominent: true, onClick: () => showConnectClaude(app) })))));
  };
  N.onAgentStatus(() => { if (el.isConnected) render(); });
  N.agentStatus().then(render);
  render();
  return el;
}

export function showAgentSettings(app: App) {
  ToolWindow.show("agentSettings", "Settings — Agents", { w: 560, h: 470 }, (w) => {
    const pad = h("div", { class: "pb-scroll", style: { padding: "18px", flex: "1" } }, agentPrefsView(app));
    w.body.append(pad);
  });
}

function jsonPath(p: string) { return p.replace(/\\/g, "\\\\"); }

/** “Connect Claude” sheet (ConnectClaudeSheet). */
export async function showConnectClaude(app: App) {
  const p = await N.paths();
  const s0 = await N.agentStatus();
  const engine = p.engine;
  const win = /\\/.test(engine) || navigator.platform.startsWith("Win");
  const project = win ? `${p.documents}\\MyProject.archi` : `${p.documents}/MyProject.archi`;
  const desktopConfig = `{\n  "mcpServers": {\n    "oanarina-archi": {\n      "command": "${jsonPath(engine)}",\n      "args": ["${jsonPath(project)}", "--mcp"]\n    }\n  }\n}`;
  const claudeCode = `claude mcp add oanarina-archi -- "${engine}" "${project}" --mcp`;
  const curl = win
    ? `$info = Get-Content "$env:APPDATA\\Oanarina Archi Tool\\agent.json" | ConvertFrom-Json\nInvoke-RestMethod -Uri http://127.0.0.1:${s0.port}/rpc -Method Post \`\n  -Headers @{ Authorization = "Bearer $($info.token)" } -ContentType "application/json" \`\n  -Body '{"jsonrpc":"2.0","id":1,"method":"run_command","params":{"command":"CIRCLE 0,0 500"}}'`
    : `curl -s http://127.0.0.1:${s0.port}/rpc \\\n  -H "Authorization: Bearer $(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("${p.agentInfo}")))["token"])')" \\\n  -d '{"jsonrpc":"2.0","id":1,"method":"run_command","params":{"command":"CIRCLE 0,0 500"}}'`;
  const sheet = new Sheet(640);
  const copied = h("div", { class: "pb-small pb-accent" });
  const step = (n: string, title: string, text: string) => h("div", { class: "pb-step" }, h("div", { class: "num", text: n }),
    h("div", { class: "pb-col", style: { gap: "3px" } }, h("div", { style: { fontWeight: "600" }, text: title }), h("div", { class: "pb-dim", text })));
  const code = (s: string) => h("div", { class: "pb-codebox" }, h("pre", { text: s }), iconButton("doc.on.doc", "Copy", async () => { await N.copy(s); copied.textContent = "Copied to the clipboard."; }));
  const body = h("div", { class: "pb-scroll pb-col", style: { padding: "18px", gap: "16px", height: "540px" } },
    step("1", "What archi-engine --mcp does", "archi-engine is installed with the app. With --mcp it becomes a Model Context Protocol server on stdin/stdout that opens (or creates) one .archi file and exposes tools: run_command (any command line such as WALL 0,0 6000,0), get_document, list_entities, add_entity, update_entity, delete, add_element, export, takeoff, check_model and the analysis tools. save writes the file, so you can open it here afterwards."),
    step("2", "Claude Desktop", "Settings ▸ Developer ▸ Edit Config, then add this to claude_desktop_config.json and restart Claude Desktop:"),
    code(desktopConfig),
    step("3", "Claude Code", "Run once in a terminal:"),
    code(claudeCode),
    step("4", "Drive this open window instead", "Start the local agent server (Settings ▸ Agents or Script ▸ Start Server). Agents send JSON-RPC 2.0 to 127.0.0.1 with the session token; the same methods are available and you watch the edits live:"),
    code(curl),
    h("div", { class: "pb-small pb-dim", text: "Replace MyProject.archi with your own file. Keep the token private: anyone with it can edit the open drawing while the server runs. The server only accepts connections from this computer." }),
    copied);
  sheet.body.append(h("div", { class: "pb-sheet-head" }, h("span", { class: "pb-accent", style: { display: "flex" } }, ico("sparkles", 15)), h("span", { text: "Connect Claude to Oanarina Archi Tool" }), spacer(),
    button("Done", { prominent: true, onClick: () => sheet.close() })), h("div", { class: "pb-hsep" }), body);
  sheet.el.style.height = "600px";
  sheet.el.dataset.sheet = "connectClaude";
}

/** The ribbon's AI Agents status block (dot, Listening/Stopped, 127.0.0.1:port, Copy token, Settings…). */
export function agentStatusBlock(app: App): HTMLElement {
  const el = h("div", { class: "agent-status" });
  const render = () => {
    const s = N.agentLast();
    clear(el);
    el.append(h("div", {}, h("span", { class: "dot", style: { background: s.running ? "#34C759" : "" } }), h("span", { text: s.running ? "Listening" : "Stopped" })),
      h("div", { style: { font: "11px var(--mono)", color: "var(--dim)" }, text: `127.0.0.1:${s.port}` }),
      h("div", { class: "rrow" },
        s.running ? button("Copy token", { compact: true, help: "Copy the session token agents must send", onClick: () => N.copy(s.token) }) : null,
        button("Settings…", { compact: true, onClick: () => app.runCommand("AGENTSETTINGS") })));
  };
  N.onAgentStatus(() => { if (el.isConnected) render(); });
  render();
  return el;
}

/** Agent `screenshot`: base64 PNG of the 2D plan of a level (Plotter.planPNG), from the engine's draw list. */
export async function planScreenshot(app: App, params: any) {
  const w = Math.min(Math.max(Number(params.width) || 1600, 16), 8192), hh = Math.min(Math.max(Number(params.height) || 1200, 16), 8192);
  const level = params.level === null ? "all" : params.level ?? undefined;
  const list = await app.engine.call("view.drawList", { level, options: { forPaper: !!params.paper }, pixelsPerUnit: 1 });
  const c = document.createElement("canvas");
  const sel = new Set((app.selection.ids ?? []).map(String));
  paintFitted(c, list, w, hh, { background: params.paper ? "#ffffff" : "#1E1F22", margin: 0.03, highlight: sel, dpr: 1, lineweights: true });
  const url = c.toDataURL("image/png");
  return { mimeType: "image/png", width: w, height: hh, image: url.slice(url.indexOf(",") + 1) };
}
