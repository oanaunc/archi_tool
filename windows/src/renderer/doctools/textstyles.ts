// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Text Styles window (AppRound12Panels.swift TextStylesPanel, TEXTSTYLEDIALOG): style list with New and Current, the
// form (Name, Font, Height (0 = set on placement), Width factor, Oblique angle (°)), a live preview "AaBb 123 Plan"
// with the width factor and slant, and Apply (textstyle.apply: the Mac TextStyleForm validation, "Text Style" undo
// step; renaming a style renames it on its text).
import type { App } from "../app";
import { h, clear } from "../dom";
import { toolWindow, flatButton, picker, windowOpen } from "../dialogs/ui";
import { cssFont } from "../canvas/drawitems";
import { FONT_FAMILIES } from "../canvas/text-editor";

interface Style { name: string; font: string; height: string; widthFactor: string; obliqueDegrees: string; strokeFont?: boolean }

export async function openTextStyles(app: App) {
  const existing = windowOpen("textStyles");
  if (existing) { existing.focus(); return existing; }
  let data = await app.tryCall("textstyle.list", {});
  let selected: string = data?.styles?.[0]?.name ?? "Standard";
  let form: Style = { ...(data?.styles?.[0] ?? { name: "Standard", font: "Helvetica", height: "0", widthFactor: "1", obliqueDegrees: "0" }) };
  let creating = false;
  let message = "";
  return toolWindow("textStyles", "Text Styles", 600, 400, (body) => {
    const root = h("div", { class: "dt-ts" });
    body.append(root);
    const num = (s: string) => Number(String(s).trim().replace(",", "."));
    const render = () => {
      clear(root);
      const list = h("div", { class: "dt-ts-list" });
      for (const s of (data?.styles ?? []) as Style[]) {
        const r = h("button", { class: "dt-ts-item" + (s.name === selected && !creating ? " sel" : ""), text: s.name });
        r.addEventListener("click", () => { selected = s.name; creating = false; message = ""; form = { ...s }; render(); });
        list.append(r);
      }
      const left = h("div", { class: "dt-ts-left" }, list, h("div", { class: "dt-ts-btns" },
        flatButton("New", () => { creating = true; form = { name: data?.newName ?? "Style 1", font: "Helvetica", height: "0", widthFactor: "1", obliqueDegrees: "0" }; message = "New style: set it up and Apply."; render(); }),
        flatButton("Current", async () => { const r = await app.tryCall("textstyle.current", { name: selected }); if (r) { message = r.message; await reload(); } })));
      const field = (label: string, key: keyof Style) => {
        const inp = h("input", { class: "darkfield", value: String(form[key] ?? "") }) as HTMLInputElement;
        inp.addEventListener("input", () => { (form as any)[key] = inp.value; updatePreview(); });
        return h("div", { class: "dt-ts-row" }, h("span", { class: "k", text: label }), inp);
      };
      const fonts = [...new Set([...(data?.fonts ?? []), ...FONT_FAMILIES, form.font])].sort((a, b) => a.localeCompare(b));
      const fontRow = h("div", { class: "dt-ts-row" }, h("span", { class: "k", text: "Font" }),
        picker(fonts.map((f) => ({ value: f, title: f })), form.font, (v) => { form.font = v; updatePreview(); }, { width: 230 }));
      const preview = h("div", { class: "dt-ts-preview" });
      const sample = h("span", { class: "dt-ts-sample", text: "AaBb 123 Plan" });
      preview.append(sample);
      const updatePreview = () => {
        const wf = Math.max(0.01, Math.min(num(form.widthFactor) || 1, 10));
        const ob = Math.max(-1.48, Math.min(((num(form.obliqueDegrees) || 0) * Math.PI) / 180, 1.48));
        const stroke = /\.shx$/i.test(form.font) || form.font === "Archi Stroke";
        sample.style.fontFamily = cssFont(stroke ? "Helvetica" : form.font);
        sample.style.transform = `matrix(${wf}, 0, ${-Math.tan(ob)}, 1, 0, 0)`;
      };
      const msg = h("span", { class: "dt-small", text: message });
      const applyBtn = flatButton("Apply", async () => {
        const r = await app.tryCall("textstyle.apply", { ...form, original: creating ? undefined : selected });
        if (!r) return;
        message = r.message ?? "";
        if (r.ok) { selected = r.name; creating = false; await reload(); } else render();
      }, { prominent: true });
      const right = h("div", { class: "dt-ts-right" }, field("Name", "name"), fontRow, field("Height (0 = set on placement)", "height"), field("Width factor", "widthFactor"),
        field("Oblique angle (°)", "obliqueDegrees"), h("div", { class: "dt-small", text: "Preview" }), preview, h("div", { class: "dt-ts-foot" }, msg, h("span", { class: "spacer" }), applyBtn));
      right.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); applyBtn.click(); } });
      root.append(left, right);
      updatePreview();
    };
    const reload = async () => {
      data = await app.tryCall("textstyle.list", {});
      const s = (data?.styles ?? []).find((x: Style) => x.name === selected);
      if (s) form = { ...s };
      await app.refresh(["drawing", "history"]);
      render();
    };
    render();
  });
}
