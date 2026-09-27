// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Customizer (CustomizerPanel.swift, M3D-093): auto-generated controls for the parameters of the selected scripted object
// (SCADOBJECT / SCRIPTCOMPONENT): sliders for ranges, pickers for choices, check boxes for booleans, Edit… for text and
// vectors. Each change regenerates the object as one undo step (customizer.set).
import type { App } from "../app";
import { h, clear, button, picker, ToolWindow, promptText, fmt, help } from "./ui";

const trimQ = (s: string) => s.replace(/^[\s"]+|[\s"]+$/g, "");

let reloadCustomizer: (() => void) | null = null;
let customizerHooked = false;

export function showCustomizer(app: App) {
  ToolWindow.show("customizer", "Customizer", { w: 400, h: 420, minW: 360, minH: 300 }, (w) => {
    const body = h("div", { class: "pb-col", style: { padding: "12px", gap: "6px", flex: "1", minHeight: "0" } });
    w.body.append(body);
    let message = "";
    let data: any = null;
    const apply = async (id: number, name: string, value: string) => {
      try { data = await app.call("customizer.set", { id, name, value }); message = ""; await app.refresh(["document"]); }
      catch (e: any) { message = e?.message ?? String(e); }
      render();
    };
    const load = async () => { data = await app.tryCall("customizer.get"); render(); };
    const control = (p: any, id: number): HTMLElement => {
      const row = h("div", { class: "pb-row", style: { gap: "6px" } });
      const label = h("span", { style: { width: "110px", flex: "none", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }, text: p.name });
      if (p.description) help(label, p.description);
      row.append(label);
      const opts: string[] = p.options ?? [];
      if (p.kind === "bool") {
        const c = h("input", { type: "checkbox" }) as HTMLInputElement;
        c.checked = String(p.value).trim() === "true";
        c.addEventListener("change", () => apply(id, p.name, c.checked ? "true" : "false"));
        row.append(c);
      } else if ((p.kind === "number" || p.kind === "string") && opts.length) {
        const vals = opts.map(trimQ);
        row.append(picker(vals, trimQ(String(p.value)), (v) => apply(id, p.name, v)));
      } else if (p.kind === "number") {
        const v = parseFloat(String(p.value).trim()) || 0;
        if (p.min !== null && p.max !== null && p.max > p.min) {
          const s = h("input", { type: "range", class: "pb-slider", min: String(p.min), max: String(p.max), step: String(p.step && p.step > 0 ? p.step : "any"), style: { flex: "1" } }) as HTMLInputElement;
          s.value = String(v);
          const out = h("span", { class: "pb-mono", style: { width: "60px", textAlign: "right" }, text: fmt(v, 3) });
          const snap = (x: number) => (p.step > 0 ? (p.min ?? 0) + Math.round((x - (p.min ?? 0)) / p.step) * p.step : x);
          s.addEventListener("input", () => { out.textContent = fmt(snap(Number(s.value)), 3); });
          s.addEventListener("change", () => apply(id, p.name, fmt(snap(Number(s.value)), 6)));
          row.append(s, out);
        } else {
          const f = h("input", { class: "pb-field", value: fmt(v, 6), style: { width: "90px" } }) as HTMLInputElement;
          f.addEventListener("keydown", (e) => { e.stopPropagation(); if (e.key === "Enter") f.blur(); });
          f.addEventListener("change", () => { const x = parseFloat(f.value); if (isFinite(x)) apply(id, p.name, fmt(x, 6)); });
          row.append(f);
        }
      } else {
        row.append(h("span", { class: "pb-mono", style: { flex: "1", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }, text: String(p.value).trim() }),
          button("Edit…", { compact: true, onClick: async () => {
            const v = await promptText(p.name, p.description || (p.kind === "vector" ? "Vector like [10, 20, 30]" : "Text value"), String(p.value).trim(), "Set");
            if (v !== null) apply(id, p.name, v);
          } }));
      }
      return row;
    };
    const render = () => {
      clear(body);
      if (data?.target !== null && data?.target !== undefined) {
        const ps: any[] = data.parameters ?? [];
        body.append(h("div", { style: { fontWeight: "600" }, text: `Scripted object #${data.target} — ${ps.length} parameter(s)` }));
        const sc = h("div", { class: "pb-scroll pb-col", style: { flex: "1", gap: "6px" } });
        const groups: string[] = [];
        for (const p of ps) if (!groups.includes(p.group ?? "")) groups.push(p.group ?? "");
        for (const g of groups) {
          if (g) sc.append(h("div", { class: "pb-dim", style: { fontWeight: "600", paddingTop: "4px" }, text: g }));
          for (const p of ps.filter((x) => (x.group ?? "") === g)) sc.append(control(p, data.target));
        }
        body.append(sc);
      } else {
        body.append(h("div", { class: "pb-dim", text: "Select a scripted object (SCADOBJECT or SCRIPTCOMPONENT) to edit its parameters." }));
      }
      if (message) body.append(h("div", { class: "pb-small", style: { color: "var(--danger, #E5534B)" }, text: message }));
    };
    reloadCustomizer = load;
    if (!customizerHooked) { customizerHooked = true; app.on(["selection", "doc"], () => { if (ToolWindow.isOpen("customizer")) reloadCustomizer?.(); }); }
    load();
  });
}
