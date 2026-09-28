// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Fixture-engine side of the graphic standards / clipboard / sharing module: the portable commands of
// Host/EngineStandardsCommands.swift answering with the same `host` notifications, and a small in-memory simulation of
// the graphicstyles / objectstyles / matpatterns / imageadjust / visualstyles / clipboard methods (same result shapes and
// messages as Host/EngineStandards.swift), so the windows can be exercised in the browser test page. Never used inside
// the Electron app.

export const STD_COMMANDS: { name: string; aliases: string[]; category: string; summary: string }[] = [
  { name: "GRAPHICSTYLES", aliases: ["STYLESMANAGER", "GSTYLES"], category: "Settings", summary: "Graphic styles manager: line styles and their layers, lineweights by view scale, pen sets and graphic override filters in one dialog." },
  { name: "OBJECTSTYLESDIALOG", aliases: ["OBJECTSTYLESDLG", "OSTYLESDIALOG"], category: "Manage", summary: "Object Styles dialog: projection/cut line weights, line colour, cut fill and cut pattern per BIM category for every plan and section." },
  { name: "MATPATTERNDIALOG", aliases: ["MATERIALPATTERNSDIALOG", "FILLPATTERNSDIALOG"], category: "Annotate", summary: "Material Fill Patterns dialog: cut and surface pattern of every material; bound hatches and floor patterns update." },
  { name: "IMAGEADJUSTDIALOG", aliases: ["IMAGEADJUSTDLG", "IADDIALOG"], category: "Blocks", summary: "Image Adjust dialog: brightness, contrast and fade of the selected raster images with a preview (exact on screen and in PDF plots)." },
  { name: "VISUALSTYLES", aliases: ["VSM", "VISUALSTYLEMANAGER"], category: "View", summary: "Visual styles manager: New/Edit a custom style from a base (edges, edge colour, face opacity, shadows, background), Delete, List, Current." },
  { name: "LWDISPLAYSCALE", aliases: ["LWSCALE"], category: "Settings", summary: "Screen display scale of lineweights (0.1–5, default 1); plotted widths are never changed." },
  { name: "PASTESPECIAL", aliases: ["PASTESPEC", "PASTEEXTERNAL", "PASTEFROMAPP"], category: "Edit", summary: "Pastes what another app copied — SVG or PDF vectors, pictures, DXF text, plain text or Explorer files — at an insertion point." },
  { name: "COPYPICTURE", aliases: ["COPYASPDF", "COPYIMAGE", "COPYPDF"], category: "Edit", summary: "Copies the selected objects (or the whole drawing) to the clipboard as a vector PDF and a PNG picture for other apps." },
  { name: "SHARE", aliases: ["SHAREDRAWING", "SENDTO"], category: "Collaborate", summary: "Shares the drawing through the Windows share sheet (Mail, Teams, Nearby Sharing…): Project (.archi), Pdf of the drawing or active sheet, or Both." },
  { name: "SPEAKDRAWING", aliases: ["DESCRIBEDRAWING", "VOICEOVERSUMMARY", "A11YSUMMARY"], category: "Help", summary: "Describes the drawing, the selection and the current prompt (spoken by Narrator / Windows speech, printed on the command line)." },
  { name: "NODEPACKAGE", aliases: ["NODEPACKAGES", "NODEPKG"], category: "Tools", summary: "Custom node packages (.archinodes): Create one from the drawing's node graph (a snippet per group), Install a file, Insert a snippet into the graph, List, Remove." },
  { name: "ARQUICKLOOK", aliases: ["ARVIEW", "USDZPREVIEW", "ARPREVIEW"], category: "View", summary: "AR view: exports the model as a real-scale glTF (GLB) and Previews it in the Windows 3D viewer (mixed reality) or Shares it to a phone or tablet." },
];
const BUILT_IN = ["Wireframe", "Hidden Line", "Shaded", "Shaded with Edges", "Conceptual", "Realistic", "X-Ray", "Sketchy"];
const CATEGORIES = ["wall", "door", "window", "opening", "slab", "ceiling", "column", "beam", "roof", "stair", "railing", "room", "area", "curtainwall", "component", "grid", "part"];
const PATTERNS = ["SOLID", "ANSI31", "ANSI32", "ANSI37", "AR-CONC", "AR-SAND", "AR-BRSTD", "EARTH", "INSUL", "WOOD"];
const OPS = ["=", "!=", "contains", "!contains", "begins", "ends", "<", "<=", ">", ">="];

interface Filter { name: string; enabled: boolean; field: string; op: string; value: string; effect: string }
const st = {
  lineStyles: [] as { key: string; name: string; color: string; lineweight: number | null; linetype: string }[],
  layerStyles: {} as Record<string, string>, lwTable: "", penSets: [] as { name: string; pens: string }[], activePenSet: "", penSetDisplay: false,
  filters: [] as Filter[], objectStyles: {} as Record<string, any>, matPatterns: {} as Record<string, { cut: string; surface: string }>,
  images: {} as Record<string, { brightness: number; contrast: number; fade: number }>, visual: [] as any[], prefs: {} as Record<string, string>,
};

function rows(t: string) {
  return t.split(";").map((p) => p.trim()).filter(Boolean).map((p) => { const [k, v] = p.split("="); const s = Number(String(k).replace(/^1:/, "")), f = Number(v); return s > 0 && f > 0 ? { scale: s, factor: f } : null; })
    .filter(Boolean).sort((a: any, b: any) => a.scale - b.scale) as { scale: number; factor: number }[];
}
function gsGet(fe: any, message = "") {
  return {
    lineStyles: st.lineStyles.map((s) => ({ ...s })), linetypes: ["Continuous", "DASHED", "HIDDEN", "CENTER"],
    layers: (fe.layers?.layers ?? fe.layerList?.() ?? [{ name: "0" }]).map((l: any) => ({ name: l.name, lineStyle: st.layerStyles[l.name] ?? "" })),
    lwTable: st.lwTable, lwRows: rows(st.lwTable).map((r) => ({ ...r, text: `1:${r.scale} → × ${r.factor}` })),
    penSets: st.penSets.map((p) => ({ ...p })), activePenSet: st.activePenSet, penSetDisplay: st.penSetDisplay,
    filters: st.filters.map((f) => ({ ...f, condition: `${f.field} ${f.op} ${f.value}` })), fields: ["layer", "type", "color", "linetype", "lineweight"], ops: OPS, message,
  };
}
function osGet() {
  return {
    rows: CATEGORIES.map((c) => ({ category: c, title: c[0].toUpperCase() + c.slice(1), projection: "", cut: "", color: null, fill: null, pattern: "", ...(st.objectStyles[c] ?? {}) })),
    patterns: PATTERNS, lineweights: ["", "0.13", "0.18", "0.25", "0.35", "0.5", "0.7", "1", "1.4", "2"],
  };
}
function materials(fe: any): string[] { return (fe.materials?.materials ?? []).map((m: any) => m.name).filter(Boolean).concat(["Concrete", "Brick", "Timber", "Glass"]).filter((v: string, i: number, a: string[]) => a.indexOf(v) === i); }
function mpGet(fe: any) { return { rows: materials(fe).map((n) => ({ name: n, cut: st.matPatterns[n]?.cut ?? "", surface: st.matPatterns[n]?.surface ?? "" })), patterns: PATTERNS }; }

export function fakeStandardsCall(fe: any, method: string, p: any): any {
  const host = (params: any) => fe.emit("host", params);
  switch (method) {
    case "engine.hello": {
      const h = fe.hello;
      if (h && Array.isArray(h.commands)) for (const c of STD_COMMANDS) if (!h.commands.some((x: any) => x.name === c.name)) h.commands.push({ ...c, modifies: c.name === "VISUALSTYLES" || c.name === "PASTESPECIAL" || c.name === "NODEPACKAGE" });
      return undefined;
    }
    case "ui.prefs": Object.assign(st.prefs, p?.values ?? {}); return undefined;
    case "graphicstyles.get": return gsGet(fe);
    case "graphicstyles.edit": {
      let message = "";
      const t = (k: string) => String(p[k] ?? "").trim();
      switch (p.op) {
        case "addLineStyle": if (t("name")) st.lineStyles.push({ key: t("name").toUpperCase(), name: t("name"), color: "", lineweight: 0.25, linetype: "" }); break;
        case "setLineStyle": { const s = st.lineStyles.find((x) => x.key === p.key); if (s) { if (p.color !== undefined) s.color = String(p.color); if ("lineweight" in p) s.lineweight = p.lineweight === null ? null : Math.min(Number(p.lineweight), 5); if (p.linetype !== undefined) s.linetype = String(p.linetype); } break; }
        case "deleteLineStyle": st.lineStyles = st.lineStyles.filter((x) => x.key !== p.key); break;
        case "setLayerLineStyle": st.layerStyles[String(p.layer)] = t("style"); break;
        case "setLwTable": { const r = rows(String(p.text ?? "")); if (!String(p.text ?? "").trim()) { st.lwTable = ""; message = "Table cleared."; } else if (!r.length) message = "No valid rows (use 1:50=1)."; else { st.lwTable = String(p.text); message = `${r.length} row(s).`; } break; }
        case "setActivePenSet": st.activePenSet = t("name"); break;
        case "setPenSetDisplay": st.penSetDisplay = !!p.on; break;
        case "deletePenSet": st.penSets = st.penSets.filter((x) => x.name !== p.name); break;
        case "savePenSet": { const n = t("name"), pens = t("pens").split(";").filter((x) => /^\d+=\d/.test(x.trim())); if (!n || !pens.length) message = "Give a name and at least one pen."; else { st.penSets = st.penSets.filter((x) => x.name !== n).concat([{ name: n, pens: pens.join(";") }]); message = `Pen set ${n}: ${pens.length} pen(s).`; } break; }
        case "setFilterEnabled": if (st.filters[p.index]) st.filters[p.index].enabled = !!p.enabled; break;
        case "raiseFilter": if (p.index > 0) { const a = st.filters; [a[p.index - 1], a[p.index]] = [a[p.index], a[p.index - 1]]; } break;
        case "deleteFilter": st.filters.splice(Number(p.index), 1); break;
        case "addFilter": {
          const eff: string[] = [];
          if (p.hide) eff.push("hidden");
          if (/^#?[0-9a-f]{6}$/i.test(t("color"))) eff.push("#" + t("color").replace("#", "").toUpperCase());
          if (t("lineweight") && Number(t("lineweight")) >= 0) eff.push(`${Number(t("lineweight"))} mm`);
          if (p.halftone) eff.push("halftone");
          if (!t("value") || !eff.length) { message = "Give a value and an override."; break; }
          st.filters.push({ name: t("name") || "Rule", enabled: true, field: t("field") || "layer", op: t("operator") || "=", value: t("value"), effect: eff.join(", ") });
          message = `Rule ${t("name") || "Rule"} added.`;
          break;
        }
      }
      fe.changed?.("document");
      return gsGet(fe, message);
    }
    case "objectstyles.get": return osGet();
    case "objectstyles.set": {
      const errors: string[] = [];
      const next: Record<string, any> = {};
      for (const r of p.rows ?? []) {
        for (const [k, n] of [["cut", "cut"], ["projection", "projection"]] as const) if (String(r[k] ?? "").trim() && !(Number(String(r[k]).replace(",", ".")) > 0)) errors.push(`${r.category}: ${n} lineweight`);
        const v = { projection: String(r.projection ?? ""), cut: String(r.cut ?? ""), color: r.color ?? null, fill: r.fill ?? null, pattern: String(r.pattern ?? "") };
        if (v.projection || v.cut || v.color || v.fill || v.pattern) next[r.category] = v;
      }
      if (errors.length) return { ok: false, message: "Check: " + errors.join(", ") };
      st.objectStyles = next;
      const n = Object.keys(next).length;
      fe.changed?.("document");
      return { ok: true, message: `${n} categor${n === 1 ? "y" : "ies"} styled.`, data: osGet() };
    }
    case "matpatterns.get": return mpGet(fe);
    case "matpatterns.set": {
      let n = 0;
      for (const r of p.rows ?? []) {
        const old = st.matPatterns[r.name] ?? { cut: "", surface: "" };
        if (old.cut !== r.cut) n++;
        if (old.surface !== r.surface) n++;
        st.matPatterns[r.name] = { cut: String(r.cut ?? ""), surface: String(r.surface ?? "") };
      }
      fe.changed?.("document");
      return { changed: n, message: `${n} pattern${n === 1 ? "" : "s"} changed.`, data: mpGet(fe) };
    }
    case "imageadjust.get": {
      const ids = (p.ids ?? []).map(Number);
      const a = st.images[String(ids[0])] ?? { brightness: 50, contrast: 50, fade: 0 };
      return { ids, ...a, path: "assets/app-icon.png", note: `${ids.length} image${ids.length === 1 ? "" : "s"} — the same result on screen, in PDF plots and after reopening.` };
    }
    case "imageadjust.set": {
      const ids = (p.ids ?? []).map(Number);
      const c = (v: any, d: number) => Math.max(0, Math.min(100, Number(v ?? d)));
      for (const id of ids) st.images[String(id)] = { brightness: c(p.brightness, 50), contrast: c(p.contrast, 50), fade: c(p.fade, 0) };
      fe.changed?.("document");
      return { adjusted: ids.length, message: `${ids.length} image${ids.length === 1 ? "" : "s"} adjusted.` };
    }
    case "visualstyles.list": return { builtIn: BUILT_IN, custom: st.visual, menu: [...BUILT_IN, ...st.visual.map((v) => v.name)], current: "Shaded with Edges" };
    case "clipboard.paste": {
      const summary = p.type === "text" ? "text" : `${String(p.type).toUpperCase()} content`;
      fe.log(`Pasted ${summary}.`);
      fe.changed?.("document", "selection");
      return { ok: true, ids: [], summary };
    }
    case "copypicture.make": return { pdf: "C:\\Temp\\ArchiCopy.pdf", svg: PICTURE_SVG, width: 120, height: 80, ratio: 100 };
    case "drawing.describe": return { text: describe(fe) };
    case "command.run": {
      const toks = String(p.line ?? "").trim().match(/"[^"]*"|\S+/g) ?? [];
      const name = (toks[0] ?? "").toUpperCase();
      const def = STD_COMMANDS.find((c) => c.name === name || c.aliases.includes(name));
      if (!def) return undefined;
      fe.log(`Command: ${name}`);
      const arg = (i: number) => (toks[i] ?? "").replace(/^"|"$/g, "");
      switch (def.name) {
        case "GRAPHICSTYLES": host({ action: "dialog", dialog: "graphicStyles" }); break;
        case "OBJECTSTYLESDIALOG": host({ action: "dialog", dialog: "objectStyles" }); break;
        case "MATPATTERNDIALOG": host({ action: "dialog", dialog: "matPatterns" }); break;
        case "IMAGEADJUSTDIALOG": {
          const ids = [...(fe.selection ?? [])].map(Number);
          if (!ids.length) { fe.log("Select one or more images."); break; }
          host({ action: "dialog", dialog: "imageAdjust", ids });
          break;
        }
        case "VISUALSTYLES": {
          const k = arg(1).toLowerCase() || "list";
          if (k === "list") { fe.log("Built-in: " + BUILT_IN.join(", ")); for (const v of st.visual) fe.log(`  ${v.name} — base ${v.base}`); }
          else if (k === "new" || k === "edit") {
            const v = { name: arg(2), base: "Shaded", edges: arg(4) ? /^y/i.test(arg(4)) : null, edgeColor: arg(7) ? "#" + arg(7).replace("#", "").toUpperCase() : null, faceOpacity: arg(5) && Number(arg(5)) < 100 ? Number(arg(5)) / 100 : null, shadows: arg(6) ? /^y/i.test(arg(6)) : null, background: null };
            st.visual = st.visual.filter((x) => x.name.toLowerCase() !== v.name.toLowerCase()).concat([v]);
            fe.log(`Visual style ${v.name} saved. VISUALSTYLES Current ${v.name} shows it.`);
          } else if (k === "delete") { st.visual = st.visual.filter((x) => x.name.toLowerCase() !== arg(2).toLowerCase()); fe.log(`Deleted ${arg(2)}.`); }
          else if (k === "current") {
            const c = st.visual.find((x) => x.name.toLowerCase() === arg(2).toLowerCase());
            const b = BUILT_IN.find((x) => x.toLowerCase().replace(/[^a-z]/g, "") === arg(2).toLowerCase().replace(/[^a-z]/g, ""));
            if (!c && !b) { fe.log(`Unknown style ${arg(2)}.`); break; }
            host({ action: "visualStyle", name: c?.name ?? b, base: c?.base ?? b, custom: c ?? null });
          }
          fe.changed?.("document");
          break;
        }
        case "LWDISPLAYSCALE": {
          const v = Number(arg(1) || st.prefs.lwDisplayScale || 1);
          if (!(v >= 0.1 && v <= 5)) { fe.log("Requires a value from 0.1 to 5."); break; }
          st.prefs.lwDisplayScale = String(v);
          host({ action: "preference", key: "lwDisplayScale", value: v });
          fe.log(`Lineweight display scale ${v}.`);
          break;
        }
        case "PASTESPECIAL": {
          if (st.prefs.clipboardExternal === "0") { fe.log("The clipboard holds nothing from another app (use PASTECLIP for drawing objects)."); break; }
          const [x, y] = (arg(1) || "0,0").split(",").map(Number);
          host({ action: "pasteSpecial", x: x || 0, y: y || 0 });
          break;
        }
        case "COPYPICTURE": host({ action: "copyPicture", pdf: "C:\\Temp\\ArchiCopy.pdf", svg: PICTURE_SVG, width: 120, height: 80, ratio: 100 }); fe.log("Copied the drawing as a PDF at 1:100 and a PNG picture."); break;
        case "SHARE": {
          const k = arg(1).toLowerCase() || "both";
          const base = String(fe.info?.title ?? "Drawing");
          const paths = [k !== "pdf" ? `C:\\Temp\\ArchiShare\\${base}.archi` : "", k !== "project" ? `C:\\Temp\\ArchiShare\\${base}.pdf` : ""].filter(Boolean);
          host({ action: "share", paths });
          fe.log(`Sharing ${paths.map((x) => x.split("\\").pop()).join(", ")}.`);
          break;
        }
        case "SPEAKDRAWING": { const t = describe(fe); fe.log(t); host({ action: "speak", text: t }); break; }
        case "NODEPACKAGE": fe.log("No node packages installed."); break;
        case "ARQUICKLOOK": {
          const path = `C:\\Temp\\ARQuickLook\\${fe.info?.title ?? "Model"}.glb`;
          host(/^s/i.test(arg(1)) ? { action: "share", paths: [path] } : { action: "openFile", path });
          fe.log(`glTF at real-world scale (0.001 m per unit): ${path}`);
          break;
        }
      }
      return { active: false, message: "Command:", keywords: [], kinds: [], preview: [] };
    }
  }
  return undefined;
}

function describe(fe: any) {
  const mode = st.prefs.viewMode ?? "2D";
  const view = mode === "3D" ? "3D view" : mode === "Sheet" ? "Sheet" : "Plan";
  const n = fe.raw?.length ?? 0;
  const sel = [...(fe.selection ?? [])];
  return `${view}, level ${fe.info?.levels?.[0]?.name ?? "Ground Floor"}, layer ${fe.sysvars?.CLAYER ?? "0"}. ${n} drawing object${n === 1 ? "" : "s"}, 0 building elements. ${sel.length ? `Selected: ${sel.length} object(s).` : "Nothing selected."} Ready for a command. Crosshair at 0, 0.`;
}

const PICTURE_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="120mm" height="80mm" viewBox="0 0 340 227"><rect width="340" height="227" fill="#ffffff"/><g transform="matrix(1 0 0 -1 0 227)"><path d="M12 12 L328 12 L328 215 L12 215 Z" fill="none" stroke="#000" stroke-width="1.4"/><path d="M12 110 L200 110" stroke="#000" stroke-width="0.7"/></g></svg>`;
