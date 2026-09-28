// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// AI assistant window (Assistant.swift, ASSISTANT; SCR-027 / SCR-035): Claude through the Anthropic Messages API or a
// local model (Ollama or any OpenAI-compatible server on this computer — nothing leaves it). The model answers with
// command lines through a `run_commands` tool (or an ```archi fenced block); the engine tries them on a copy of the
// drawing first (assistant.assess), bulk changes wait for Apply / Discard, then they run as normal, undoable commands
// (assistant.apply). Requests go out from the main process (workspace native); the API key is stored encrypted.
import type { App } from "../app";
import { ToolWindow, button, iconButton, field, picker } from "../partb/ui";
import { h, clear } from "../dom";
import { icon } from "../icons";
import { help } from "../ui/menu";
import { WS } from "./native";

export type Provider = "anthropic" | "local";
export const PROVIDERS: [Provider, string][] = [["anthropic", "Claude (Anthropic API)"], ["local", "Local model (Ollama / OpenAI-compatible)"]];
export interface AssistantConfig { provider: Provider; model: string; endpoint: string; bulkLimit: number; deleteLimit: number }
const DEFAULT: AssistantConfig = { provider: "local", model: "llama3.1", endpoint: "http://127.0.0.1:11434/v1/chat/completions", bulkLimit: 25, deleteLimit: 5 };
export const DEFAULT_CLAUDE_MODEL = "claude-sonnet-4-5";
const CKEY = "archi.assistant.config";

export function loadConfig(): AssistantConfig { try { return { ...DEFAULT, ...JSON.parse(localStorage.getItem(CKEY) ?? "{}") }; } catch { return { ...DEFAULT }; } }
function saveConfig(c: AssistantConfig) { try { localStorage.setItem(CKEY, JSON.stringify({ provider: c.provider, model: c.model, endpoint: c.endpoint, bulkLimit: c.bulkLimit })); } catch {} }

interface Msg { role: "user" | "assistant" | "system"; text: string; commands: string[] }

// ---- protocol (AssistantProtocol) ----
const TOOL = "run_commands";
function schema() { return { type: "object", properties: { commands: { type: "array", items: { type: "string" } } }, required: ["commands"] }; }
export function anthropicBody(model: string, system: string, messages: Msg[], description: string) {
  return { model, max_tokens: 2048, system, messages: messages.filter((m) => m.role !== "system").map((m) => ({ role: m.role, content: m.text })), tools: [{ name: TOOL, description, input_schema: schema() }] };
}
export function openAIBody(model: string, system: string, messages: Msg[], description: string) {
  return { model, stream: false, messages: [{ role: "system", content: system }, ...messages.filter((m) => m.role !== "system").map((m) => ({ role: m.role, content: m.text }))],
    tools: [{ type: "function", function: { name: TOOL, description, parameters: schema() } }] };
}
export function fencedCommands(text: string): string[] {
  const out: string[] = [];
  let inBlock = false;
  for (const line of text.split("\n")) {
    const t = line.trim();
    if (t.startsWith("```")) { if (inBlock) inBlock = false; else if (/^```(archi|commands)/i.test(t)) inBlock = true; continue; }
    if (inBlock && t) out.push(line.endsWith(" ") ? line : line + " ");
  }
  return out;
}
/** Text and command lines of a reply from either API; ```archi blocks count as commands too. */
export function parseReply(raw: string): { text: string; commands: string[] } | null {
  let obj: any;
  try { obj = JSON.parse(raw); } catch { return null; }
  let text = "", cmds: string[] = [];
  if (Array.isArray(obj?.content)) {
    for (const b of obj.content) {
      if (b?.type === "text" && typeof b.text === "string") text += b.text;
      if (b?.type === "tool_use" && b.name === TOOL && Array.isArray(b.input?.commands)) cmds.push(...b.input.commands.map(String));
    }
  } else if (Array.isArray(obj?.choices) && obj.choices[0]?.message) {
    const msg = obj.choices[0].message;
    text = typeof msg.content === "string" ? msg.content : "";
    for (const call of msg.tool_calls ?? []) {
      const f = call?.function;
      if (!f || f.name !== TOOL) continue;
      let a = f.arguments;
      if (typeof a === "string") { try { a = JSON.parse(a); } catch { a = null; } }
      if (Array.isArray(a?.commands)) cmds.push(...a.commands.map(String));
    }
  } else if (obj?.error) return { text: `Error: ${obj.error.message ?? "unknown"}`, commands: [] };
  else return null;
  if (!cmds.length) cmds = fencedCommands(text);
  return { text: text.trim(), commands: cmds.map((c) => c.replace(/[\r\n]+/g, "")).filter((c) => c.trim()) };
}

// ---- session (AssistantSession) ----
class Session {
  messages: Msg[] = [];
  busy = false;
  config = loadConfig();
  pending: { commands: string[]; summary: string } | null = null;
  onChange: () => void = () => {};
  constructor(private app: App) {}
  private push(m: Msg) { this.messages.push(m); this.onChange(); }

  async send(text: string) {
    if (!text.trim() || this.busy) return;
    this.push({ role: "user", text, commands: [] });
    this.busy = true; this.onChange();
    try {
      const ctx = await this.app.tryCall("assistant.context", {});
      if (!ctx) { this.push({ role: "system", text: "Request failed: the engine did not describe the drawing.", commands: [] }); return; }
      const c = this.config;
      const body = c.provider === "anthropic" ? anthropicBody(c.model, ctx.system, this.messages, ctx.toolDescription) : openAIBody(c.model, ctx.system, this.messages, ctx.toolDescription);
      const r = await WS.assistantRequest({ provider: c.provider, endpoint: c.endpoint, body });
      if (r.error) { this.push({ role: "system", text: `Request failed: ${r.error}`, commands: [] }); return; }
      const reply = parseReply(r.text ?? "");
      if (!reply) { this.push({ role: "system", text: "Unreadable reply from the model.", commands: [] }); return; }
      this.push({ role: "assistant", text: reply.text || "(commands only)", commands: reply.commands });
      if (reply.commands.length) await this.propose(reply.commands);
    } finally { this.busy = false; this.onChange(); }
  }
  /** Measures the change on a copy; runs it directly or waits for confirmation when it is a bulk change. */
  async propose(commands: string[]) {
    const im = await this.app.tryCall("assistant.assess", { commands, bulkLimit: this.config.bulkLimit, deleteLimit: this.config.deleteLimit });
    if (im?.bulk) {
      this.pending = { commands, summary: String(im.summary) };
      this.push({ role: "system", text: `This would change many objects (${im.summary}). Apply or discard?`, commands: [] });
    } else await this.apply(commands);
  }
  async apply(commands: string[]) {
    this.pending = null;
    const r = await this.app.tryCall("assistant.apply", { commands });
    const out: string[] = r?.output ?? [];
    await this.app.refresh(["document", "selection"]);
    this.push({ role: "system", text: `Ran ${commands.length} command(s) — undo with Ctrl+Z.` + (out.length ? "\n" + out.slice(-6).join("\n") : ""), commands: [] });
  }
  discard() { this.pending = null; this.push({ role: "system", text: "Changes discarded.", commands: [] }); }
}

let session: Session | null = null;
export function assistantSession(app: App) { return (session ??= new Session(app)); }

export function showAssistant(app: App, ask?: string) {
  const s = assistantSession(app);
  let showSettings = false;
  ToolWindow.show("assistant", `Assistant — ${app.info?.title ?? "Untitled"}`, { w: 460, h: 640, minW: 340, minH: 360 }, (w) => {
    const headTitle = h("span", { class: "ws-bold" });
    const gear = iconButton("gearshape", "Provider, model and key", () => { showSettings = !showSettings; render(); });
    const settingsBox = h("div", { class: "ws-as-settings" });
    const msgs = h("div", { class: "ws-as-msgs" });
    const pendingBar = h("div", { class: "ws-as-pending" });
    const input = h("textarea", { class: "ws-as-input", rows: 1, placeholder: "Ask or describe a change (e.g. “add a 5 m wall from 0,0 to the east”)" }) as HTMLTextAreaElement;
    const sendBtn = h("button", { class: "iconbtn ws-as-send" }, icon("paperplane.fill", 14)) as HTMLButtonElement;
    help(sendBtn, "Send");
    const submit = () => { const t = input.value; input.value = ""; fitInput(); void s.send(t); };
    const fitInput = () => { input.rows = Math.min(4, Math.max(1, input.value.split("\n").length)); sendBtn.disabled = s.busy || !input.value.trim(); };
    input.addEventListener("input", fitInput);
    input.addEventListener("keydown", (e) => { e.stopPropagation(); if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); submit(); } });
    sendBtn.addEventListener("click", submit);
    w.body.append(h("div", { class: "ws-assistant" }, h("div", { class: "ws-row ws-as-head" }, h("span", { class: "ws-accent" }, icon("sparkles", 14)), headTitle, h("span", { class: "ws-spacer" }), gear),
      settingsBox, h("div", { class: "hsep" }), msgs, pendingBar, h("div", { class: "hsep" }), h("div", { class: "ws-row ws-as-foot" }, input, sendBtn)));

    const renderSettings = () => {
      clear(settingsBox);
      settingsBox.style.display = showSettings ? "" : "none";
      if (!showSettings) return;
      const c = s.config;
      const key = field({ type: "password", placeholder: "Anthropic API key (stored encrypted for your Windows account)", flex: true });
      const model = field({ value: c.model, flex: true, onInput: (v) => { c.model = v; } });
      const endpoint = field({ value: c.endpoint, flex: true, onInput: (v) => { c.endpoint = v; } });
      const limit = h("input", { type: "number", min: "1", max: "500", value: String(c.bulkLimit), class: "ws-num" }) as HTMLInputElement;
      const limitLabel = h("span", { text: `Confirm above ${c.bulkLimit} changes` });
      limit.addEventListener("input", () => { const v = Math.round(Number(limit.value)); if (v >= 1 && v <= 500) { c.bulkLimit = v; limitLabel.textContent = `Confirm above ${v} changes`; } });
      limit.addEventListener("keydown", (e) => e.stopPropagation());
      settingsBox.append(
        h("div", { class: "ws-row" }, h("span", { class: "ws-lbl", text: "Provider" }), picker(PROVIDERS.map(([v, label]) => ({ value: v, label })), c.provider, (v) => { c.provider = v as Provider; renderSettings(); })),
        h("div", { class: "ws-row" }, h("span", { class: "ws-lbl", text: "Model" }), model),
        ...(c.provider === "local"
          ? [h("div", { class: "ws-row" }, h("span", { class: "ws-lbl", text: "Endpoint (localhost)" }), endpoint),
             h("div", { class: "psub", text: "Runs on this computer: the drawing context never leaves it. Ollama: `ollama serve`, then pull a model with tool support." })]
          : [h("div", { class: "ws-row" }, key), h("div", { class: "psub", text: "The drawing summary and your messages are sent to Anthropic." })]),
        h("div", { class: "ws-row" }, limitLabel, limit, h("span", { class: "ws-spacer" }), button("Save", { prominent: true, onClick: async () => {
          if (c.provider === "anthropic" && c.model === "llama3.1") c.model = DEFAULT_CLAUDE_MODEL;
          saveConfig(c);
          if (key.value) { await WS.assistantSetKey(key.value); key.value = ""; }
          showSettings = false; render();
        } })));
    };
    const renderMessages = () => {
      clear(msgs);
      for (const m of s.messages) {
        const b = h("div", { class: `ws-bubble ${m.role}` }, h("div", { class: "t", text: m.text }), m.commands.length ? h("pre", { class: "c", text: m.commands.join("\n") }) : null);
        msgs.append(b);
      }
      if (s.busy) msgs.append(h("div", { class: "ws-spinner" }));
      msgs.scrollTop = 1e9;
      clear(pendingBar);
      pendingBar.style.display = s.pending ? "" : "none";
      if (s.pending) {
        const p = s.pending;
        pendingBar.append(h("span", { class: "pb-small", text: `Bulk change: ${p.summary}` }), h("span", { class: "ws-spacer" }),
          button("Discard", { onClick: () => s.discard() }), button("Apply", { prominent: true, onClick: () => void s.apply(p.commands) }));
      }
      sendBtn.disabled = s.busy || !input.value.trim();
    };
    const render = () => {
      headTitle.textContent = s.config.provider === "local" ? `Local: ${s.config.model}` : `Claude: ${s.config.model}`;
      gear.classList.toggle("active", showSettings);
      renderSettings(); renderMessages();
    };
    s.onChange = () => { if (ToolWindow.isOpen("assistant")) renderMessages(); };
    render();
    setTimeout(() => input.focus(), 0);
  });
  if (ask) void s.send(ask);
}
