// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// The round-12 dialogs of AppRound12Panels.swift: Object Styles (OBJECTSTYLESDIALOG: projection / cut lineweights, line
// colour, cut fill and cut pattern per BIM category), Material Fill Patterns (MATPATTERNDIALOG: cut and surface pattern
// of every material) and Image Adjust (IMAGEADJUSTDIALOG: brightness, contrast and fade with a live preview computed with
// ImageDisplay.adjusted, the per-pixel model the screen and PDF output reproduce). Each Apply is one undo step.
import type { App } from "../app";
import { h, clear } from "../dom";
import { toolWindow, flatButton, picker, textField, slider, label, note, spacer } from "../dialogs/ui";
import { showMenu } from "../ui/menu";
import { imageUrl } from "../canvas/drawitems";

// ---- Object Styles ----

interface OSRow { category: string; title: string; projection: string; cut: string; color: string | null; fill: string | null; pattern: string }

export async function openObjectStyles(app: App) {
  let data = await app.tryCall("objectstyles.get", {});
  if (!data) return null;
  let rows: OSRow[] = data.rows.map((r: OSRow) => ({ ...r }));
  let message = "";
  return toolWindow("objectStyles", "Object Styles", 700, 520, (body) => {
    const root = h("div", { class: "gs-win" });
    body.append(root);
    const weights: string[] = data.lineweights;
    const patterns: string[] = data.patterns;
    const weightField = (r: OSRow, key: "projection" | "cut") => {
      const f = textField("", r[key], (v) => { r[key] = v; }, { width: 46 });
      const m = h("button", { class: "gs-menu", "aria-label": "Lineweights", text: "▾" });
      m.addEventListener("click", () => showMenu(weights.map((w) => ({ title: w || "Default", action: () => { r[key] = w; f.value = w; } })), m));
      return h("span", { class: "gs-wf" }, f, m);
    };
    const colorField = (r: OSRow, key: "color" | "fill") => {
      const on = h("input", { type: "checkbox", class: "gs-chk" }) as HTMLInputElement;
      on.checked = r[key] !== null;
      const c = h("input", { type: "color", class: "gs-color" }) as HTMLInputElement;
      c.value = (r[key] ?? "#808080").toLowerCase();
      c.disabled = !on.checked;
      on.addEventListener("change", () => { r[key] = on.checked ? c.value.toUpperCase() : null; c.disabled = !on.checked; });
      c.addEventListener("input", () => { r[key] = c.value.toUpperCase(); });
      return h("span", { class: "gs-cf" }, on, c);
    };
    const render = () => {
      clear(root);
      root.append(note("Category-wide graphics for every plan and section: projection and cut line weights (mm), line colour, cut fill and cut pattern. Empty = default."));
      root.append(h("div", { class: "drow gs-head" }, label("Category", { width: 96, bold: true }), label("Projection", { width: 78, bold: true }), label("Cut", { width: 78, bold: true }),
        label("Line colour", { width: 96, bold: true }), label("Cut fill", { width: 96, bold: true }), label("Cut pattern", { bold: true })));
      const list = h("div", { class: "gs-page" });
      for (const r of rows) {
        const el = h("div", { class: "drow gs-row", "aria-label": `${r.category} object style` },
          label(r.title, { width: 96 }), weightField(r, "projection"), weightField(r, "cut"), colorField(r, "color"), colorField(r, "fill"),
          picker([{ value: "", title: "Default" }, ...patterns.map((p) => ({ value: p, title: p }))], r.pattern, (v) => { r.pattern = v; }, { width: 120 }));
        list.append(el);
      }
      root.append(list, h("div", { class: "drow" }, h("span", { class: "gs-msg", text: message }), spacer(),
        flatButton("Reset All", () => { rows = rows.map((r) => ({ ...r, projection: "", cut: "", color: null, fill: null, pattern: "" })); message = ""; render(); }),
        flatButton("Apply", async () => {
          const r = await app.tryCall("objectstyles.set", { rows });
          if (!r) return;
          message = r.message ?? "";
          if (r.ok && r.data) { data = r.data; rows = r.data.rows.map((x: OSRow) => ({ ...x })); }
          await app.refresh(["drawing", "history"]);
          render();
        }, { prominent: true })));
    };
    render();
  });
}

// ---- Material Fill Patterns ----

export async function openMatPatterns(app: App) {
  const data = await app.tryCall("matpatterns.get", {});
  if (!data) return null;
  let rows: { name: string; cut: string; surface: string }[] = data.rows.map((r: any) => ({ ...r }));
  let message = "";
  return toolWindow("matPatterns", "Material Fill Patterns", 560, 420, (body) => {
    const root = h("div", { class: "gs-win" });
    body.append(root);
    const names = (cur: string) => [...new Set([...(data.patterns as string[]), ...(cur ? [cur] : [])])].sort();
    const pick = (r: any, key: "cut" | "surface") => picker([{ value: "", title: "None" }, ...names(r[key]).map((p) => ({ value: p, title: p }))], r[key], (v) => { r[key] = v; }, { width: 150 });
    const render = () => {
      clear(root);
      root.append(note("Cut patterns fill materials cut in plan and section; surface patterns fill floors and faces seen in projection. Hatches bound to a material follow."));
      root.append(h("div", { class: "drow gs-head" }, label("Material", { width: 160, bold: true }), label("Cut pattern", { width: 150, bold: true }), label("Surface pattern", { bold: true })));
      const list = h("div", { class: "gs-page" });
      for (const r of rows) list.append(h("div", { class: "drow gs-row" }, label(r.name, { width: 160 }), pick(r, "cut"), pick(r, "surface")));
      root.append(list, h("div", { class: "drow" }, h("span", { class: "gs-msg", text: message }), spacer(),
        flatButton("Apply", async () => {
          const r = await app.tryCall("matpatterns.set", { rows });
          if (!r) return;
          message = r.message ?? "";
          if (r.data) rows = r.data.rows.map((x: any) => ({ ...x }));
          await app.refresh(["drawing", "history"]);
          render();
        }, { prominent: true })));
    };
    render();
  });
}

// ---- Image Adjust ----

/** ImageDisplay.adjusted: contrast around mid grey, brightness towards white / black, fade towards the background. */
export function adjustPixel(v: number, bg: number, a: { brightness: number; contrast: number; fade: number }): number {
  let x = v;
  if (a.contrast >= 50) x = 0.5 + (x - 0.5) * (a.contrast >= 100 ? 50 : 50 / (100 - a.contrast)); else x = x + (0.5 - x) * (50 - a.contrast) / 50;
  x = Math.max(0, Math.min(1, x));
  if (a.brightness > 50) x = x + (1 - x) * (a.brightness - 50) / 50; else if (a.brightness < 50) x = x * (1 - (50 - a.brightness) / 50);
  x = x + (bg - x) * a.fade / 100;
  return Math.max(0, Math.min(1, x));
}

export async function openImageAdjust(app: App, ids: number[]) {
  const d = await app.tryCall("imageadjust.get", { ids });
  if (!d || !d.ids?.length) return null;
  const a = { brightness: Number(d.brightness), contrast: Number(d.contrast), fade: Number(d.fade) };
  let message = "";
  document.querySelector('[data-window="imageAdjust"]')?.remove();
  return toolWindow("imageAdjust", "Image Adjust", 420, 380, (body) => {
    const root = h("div", { class: "gs-win" });
    body.append(root);
    const canvas = h("canvas", { class: "gs-thumb" }) as HTMLCanvasElement;
    let src: ImageData | null = null;
    const draw = () => {
      if (!src) return;
      const ctx = canvas.getContext("2d")!;
      const out = ctx.createImageData(src.width, src.height);
      const lut = new Uint8ClampedArray(256);
      for (let i = 0; i < 256; i++) lut[i] = Math.round(adjustPixel(i / 255, 1, a) * 255);
      for (let i = 0; i < src.data.length; i += 4) { out.data[i] = lut[src.data[i]]; out.data[i + 1] = lut[src.data[i + 1]]; out.data[i + 2] = lut[src.data[i + 2]]; out.data[i + 3] = src.data[i + 3]; }
      ctx.putImageData(out, 0, 0);
    };
    if (d.path) {
      const img = new Image();
      img.onload = () => {
        const k = Math.min(1, 380 / img.naturalWidth, 180 / img.naturalHeight);
        canvas.width = Math.max(1, Math.round(img.naturalWidth * k)); canvas.height = Math.max(1, Math.round(img.naturalHeight * k));
        const ctx = canvas.getContext("2d")!;
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        try { src = ctx.getImageData(0, 0, canvas.width, canvas.height); draw(); } catch { /* tainted */ }
      };
      img.src = imageUrl(String(d.path));
    }
    const msg = h("span", { class: "gs-msg" });
    const sliders: Record<string, { s: HTMLInputElement; v: HTMLElement }> = {};
    const row = (title: string, key: keyof typeof a) => {
      const v = label(String(Math.round(a[key])), { width: 32 });
      const s = slider(0, 100, 1, a[key], (x) => { a[key] = x; v.textContent = String(Math.round(x)); draw(); }, 260);
      sliders[key] = { s, v };
      return h("div", { class: "drow gs-row" }, label(title, { width: 80 }), s, v);
    };
    root.append(note(d.note ?? ""), canvas, row("Brightness", "brightness"), row("Contrast", "contrast"), row("Fade", "fade"),
      h("div", { class: "drow" }, msg, spacer(),
        flatButton("Reset", () => { a.brightness = 50; a.contrast = 50; a.fade = 0; for (const k of Object.keys(sliders)) { sliders[k].s.value = String((a as any)[k]); sliders[k].v.textContent = String((a as any)[k]); } draw(); }),
        flatButton("Apply", async () => {
          const r = await app.tryCall("imageadjust.set", { ids: d.ids, ...a });
          if (!r) return;
          message = r.message ?? ""; msg.textContent = message;
          await app.refresh(["drawing", "history"]);
        }, { prominent: true })));
  });
}
