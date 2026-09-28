// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Status bar (StatusBarView.swift): coordinates, WCS, drafting toggles, level and layer, isolate, annotation scale,
// quick properties, units, zoom, agent server.
import { App, TOGGLES } from "../app";
import { h, clear } from "../dom";
import { icon } from "../icons";
import { help, showMenu } from "./menu";
import { layerDropdown, levelDropdown } from "./dropdowns";
import { hasIcon } from "../icons";
import { progress } from "../workspace/progress";
import { agentStatus, onAgentStatus } from "../partb/native";
import { toggleAgentServer } from "../partb/agents";

const UNITS: [string, string][] = [["millimeters", "mm"], ["centimeters", "cm"], ["meters", "m"], ["inches", "in"], ["feet", "ft"]];
export function unitAbbrev(u?: string) { return UNITS.find(([n]) => n === (u ?? "").toLowerCase())?.[1] ?? (u || "mm"); }

export class StatusBar {
  el: HTMLElement;
  private xy = h("span", { class: "xy", text: "0.00, 0.00" });
  private unit = h("span", { class: "u", text: "mm" });
  private snap = h("span", { class: "snap" });
  private toggles = h("div", { class: "toggles" });
  private right = h("div", { class: "right" });
  private macros = h("div", { class: "macros" });
  private prog = h("div", { class: "progress" });
  private agent = { running: false, port: 0 };

  constructor(private app: App) {
    const wcs = h("button", { class: "tog", text: "WCS", style: { marginRight: "6px" } });
    help(wcs, "World coordinate system — coordinates are world X,Y");
    wcs.addEventListener("click", () => showMenu([["World (WCS)", "UCS W"], ["Previous", "UCS P"], ["New Origin…", "UCS O"], ["Rotate About Z…", "UCS Z"], ["3 Points…", "UCS 3"], ["Align to Object…", "UCS OB"]]
      .map(([t, c]) => ({ title: t, action: () => app.runCommand(c) })).concat([{ separator: true } as any, { title: "Named UCS…", action: () => app.runCommand("UCSMAN") }]), wcs));
    this.el = h("div", { class: "statusbar" },
      h("div", { class: "coords" }, this.xy, this.unit, this.snap), wcs, this.macros, h("div", { class: "vsep" }), this.toggles, h("div", { class: "vsep" }),
      h("div", { style: { padding: "0 4px" } }, levelDropdown(app, 150)), h("div", { style: { paddingRight: "4px" } }, layerDropdown(app, 130)), this.right);
    this.renderToggles(); this.renderRight();
    app.on("sysvars", () => this.renderToggles());
    app.on(["doc", "selection", "ui", "sysvars"], () => this.renderRight());
    app.on("live", () => this.renderLive());
    // Macro buttons (MacroButtonBar), the progress of long jobs (ProgressStatusView), Quick Properties and agent state.
    app.on(["doc", "drawing"], () => void this.renderMacros());
    progress.on(() => this.renderProgress());
    document.addEventListener("archi:quickprops", () => this.renderRight());
    onAgentStatus((st: any) => { this.agent = { running: !!st?.running, port: Number(st?.port ?? 0) }; this.renderRight(); });
    void agentStatus().then((st: any) => { this.agent = { running: !!st?.running, port: Number(st?.port ?? 0) }; this.renderRight(); }).catch(() => {});
    void this.renderMacros();
  }
  /** Custom macro buttons (CMD-041, MACROBUTTON): user-profile and drawing buttons, run like AutoCAD CUI macros. */
  private async renderMacros() {
    const list: any[] = (await this.app.tryCall("macro.buttons", {})) ?? [];
    clear(this.macros);
    if (!Array.isArray(list) || !list.length) return;
    const run = (b: any) => void this.app.tryCall("macro.run", { macro: String(b.macro) }).then((st) => { if (st) this.app.setPrompt(st); this.app.canvas?.focus(); });
    this.macros.append(h("div", { class: "vsep" }));
    for (const b of list.slice(0, 12)) {
      const btn = h("button", { class: "macro" }, icon(hasIcon(String(b.icon)) ? String(b.icon) : "command", 12));
      help(btn, b.tooltip ? String(b.tooltip) : `${b.name}: ${b.macro}`);
      btn.addEventListener("click", () => run(b));
      this.macros.append(btn);
    }
    if (list.length > 12) {
      const more = h("button", { class: "macro" }, icon("ellipsis", 12));
      help(more, "More macro buttons");
      more.addEventListener("click", () => showMenu(list.slice(12).map((b) => ({ title: String(b.name), action: () => run(b) })), more));
      this.macros.append(more);
    }
  }
  private renderProgress() {
    clear(this.prog);
    const j = progress.current;
    if (!j) return;
    const bar = j.fraction === null ? h("span", { class: "spin" }) : h("span", { class: "bar" }, h("span", { class: "fill", style: { width: `${Math.round(j.fraction * 100)}%` } }));
    const cancel = h("button", { class: "cancel" }, icon("xmark.circle.fill", 12));
    help(cancel, `Cancel ${j.title}`);
    cancel.addEventListener("click", () => progress.cancel(j.id));
    this.prog.append(bar, h("span", { class: "t", text: j.title + (j.detail ? " · " + j.detail : "") }), cancel);
  }
  private renderToggles() {
    clear(this.toggles);
    for (const t of TOGGLES) {
      const on = this.app.sysvarOn(t.varName);
      const b = h("button", { class: "tog" + (on ? " on" : ""), text: t.title });
      help(b, `${t.title} ${on ? "on" : "off"}${t.key ? ` (${t.key})` : ""}`);
      b.setAttribute("aria-pressed", String(on));
      b.addEventListener("click", () => this.app.toggleVar(t.varName, t.title));
      this.toggles.append(b);
    }
  }
  renderLive() {
    const l = this.app.live;
    this.xy.textContent = `${l.x.toFixed(2)}, ${l.y.toFixed(2)}`;
    this.snap.textContent = l.snapHint ?? "";
    const z = this.right.querySelector(".zoom");
    if (z) z.textContent = `Zoom ${zoomText(l.zoomPercent)}`;
  }
  private renderRight() {
    const app = this.app;
    this.unit.textContent = unitAbbrev(app.info?.units);
    clear(this.right);
    if (app.selection.ids.length) this.right.append(h("span", { class: "sel" }, icon("cursorarrow.rays", 11), h("span", { text: `${app.selection.ids.length} selected` })));
    this.right.append(this.prog);
    const iso = h("button", {}, icon("eye", 13)); help(iso, "Isolate or hide the selected objects");
    iso.addEventListener("click", () => showMenu([{ title: "Isolate Selection", disabled: !app.selection.ids.length, action: () => app.runCommand("ISOLATEOBJECTS") },
      { title: "Hide Selection", disabled: !app.selection.ids.length, action: () => app.runCommand("HIDEOBJECTS") }, { separator: true }, { title: "End Isolation", action: () => app.runCommand("UNISOLATEOBJECTS") }], iso));
    const ann = h("button", {}, icon("square.3.layers.3d.middle.filled", 13), h("span", { text: app.sysvars.CANNOSCALE ?? "1:1", style: { color: "var(--text)", fontSize: "11px" } }));
    help(ann, "Annotation scale");
    ann.addEventListener("click", () => showMenu(["1:1", "1:5", "1:10", "1:20", "1:50", "1:100", "1:200", "1:500"].map((s) => ({ title: s, checked: s === (app.sysvars.CANNOSCALE ?? "1:1"), action: () => app.setVar("CANNOSCALE", s) })), ann));
    // Quick Properties over the drawing (doctools QuickPropsOverlay): the button toggles it and shows its state.
    const qpo = (window as any).archiDocTools?.quickProps;
    const qpOn = !!qpo?.on;
    const qp = h("button", { class: qpOn ? "on" : "" }, icon("slider.horizontal.below.rectangle", 13)); help(qp, `Quick Properties (QP) ${qpOn ? "on" : "off"}`);
    qp.addEventListener("click", () => { if (qpo) { qpo.on = !qpo.on; this.renderRight(); } else void app.action("@panel:Quick Props"); });
    const units = h("button", { text: unitAbbrev(app.info?.units), style: { color: "var(--text)", fontSize: "11px" } }); help(units, "Drawing units");
    units.addEventListener("click", () => showMenu(UNITS.map(([n]) => ({ title: n[0].toUpperCase() + n.slice(1), checked: n === app.info?.units, action: () => app.setVar("INSUNITS", n) })), units));
    const zoom = h("span", { class: "zoom", text: `Zoom ${zoomText(app.live.zoomPercent)}` }); help(zoom, "Screen scale relative to real size");
    const ag = this.agent;
    const agent = h("button", { class: "agent" + (ag.running ? " on" : "") }, h("span", { class: "agent-dot" }), h("span", { text: ag.running ? `Agent: on :${ag.port}` : "Agent: off" }));
    help(agent, ag.running ? `Agent server listening on 127.0.0.1:${ag.port} — click to stop` : "Start the local agent server");
    agent.addEventListener("click", () => void toggleAgentServer(app).then(() => agentStatus()).catch(() => app.runCommand("AGENTSERVER")));
    this.right.append(iso, ann, qp, units, zoom, agent);
  }
}
export function zoomText(p: number) {
  if (!(p > 0) || !isFinite(p)) return "—";
  if (p >= 100) return `${(p / 100).toFixed(1)}:1`;
  return `1:${Math.round(100 / p)}`;
}
