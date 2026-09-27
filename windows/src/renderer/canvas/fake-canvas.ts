// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Fixture-engine side of the canvas methods (docs/ENGINE-PROTOCOL.md "Canvas"): when the renderer runs as a web page
// with the fake engine (tests, design review), these simulate canvas.state, grips.actions / preview / edit / typed,
// select.lasso / modify / chain / nudge, pick.candidates, canvas.doubleClick, text.edit, tempdims.*, flips.*,
// palette.items, place.*, file.drop and sheet.viewport(s) on the fake drawing, with the engine's result shapes. Recorded
// canvas-*.json fixtures are used for the parts the fake drawing cannot know. Never used inside the Electron app.
import { distance } from "./drawitems";
type V2 = [number, number];
const PREVIEW = "#dbe0eb";

function pointInPoly(q: V2, l: V2[]) {
  let c = false;
  for (let i = 0, j = l.length - 1; i < l.length; j = i++) {
    if ((l[i][1] > q[1]) !== (l[j][1] > q[1]) && q[0] < ((l[j][0] - l[i][0]) * (q[1] - l[i][1])) / (l[j][1] - l[i][1]) + l[i][0]) c = !c;
  }
  return c;
}
function signedArea(l: V2[]) { let a = 0; for (let i = 0; i < l.length; i++) { const p = l[i], q = l[(i + 1) % l.length]; a += p[0] * q[1] - q[0] * p[1]; } return a / 2; }
function mapPoints(it: any, f: (p: V2) => V2) {
  if (it.points) it.points = it.points.map((p: V2) => f(p));
  if (it.loops) it.loops = it.loops.map((l: V2[]) => l.map((p) => f(p)));
  if (it.text?.position) it.text.position = f(it.text.position);
}
function transformFor(mode: string, o: V2, p: V2, reference: number): ((q: V2) => V2) | null {
  const dx = p[0] - o[0], dy = p[1] - o[1];
  switch (mode) {
    case "move": return (q) => [q[0] + dx, q[1] + dy];
    case "rotate": { const a = Math.atan2(dy, dx), c = Math.cos(a), s = Math.sin(a); return (q) => [o[0] + (q[0] - o[0]) * c - (q[1] - o[1]) * s, o[1] + (q[0] - o[0]) * s + (q[1] - o[1]) * c]; }
    case "scale": { const k = Math.hypot(dx, dy) / Math.max(reference, 1e-9); if (k < 1e-9) return null; return (q) => [o[0] + (q[0] - o[0]) * k, o[1] + (q[1] - o[1]) * k]; }
    case "mirror": {
      const l = Math.hypot(dx, dy); if (l < 1e-9) return null;
      const ux = dx / l, uy = dy / l;
      return (q) => { const vx = q[0] - o[0], vy = q[1] - o[1], t = vx * ux + vy * uy; return [o[0] + 2 * t * ux - vx, o[1] + 2 * t * uy - vy]; };
    }
  }
  return null;
}
const COMPONENTS = [
  { id: "chair", name: "Chair", category: "Furniture", size: [500, 520, 850] },
  { id: "table", name: "Table", category: "Furniture", size: [1600, 900, 740] },
  { id: "sofa", name: "Sofa", category: "Furniture", size: [2100, 900, 800] },
  { id: "bed", name: "Bed", category: "Furniture", size: [1600, 2000, 450] },
  { id: "desk", name: "Desk", category: "Furniture", size: [1400, 700, 740] },
  { id: "wc", name: "WC", category: "Sanitary", size: [380, 650, 400] },
];
function componentShapes(size: number[], at: V2 = [0, 0], turns = 0): V2[][] {
  const a = (((turns % 4) + 4) % 4) * (Math.PI / 2), c = Math.cos(a), s = Math.sin(a);
  const r = (x: number, y: number): V2 => [at[0] + x * c - y * s, at[1] + x * s + y * c];
  const hw = size[0] / 2, hd = size[1] / 2;
  return [[r(-hw, -hd), r(hw, -hd), r(hw, hd), r(-hw, hd), r(-hw, -hd)], [r(-hw * 0.8, hd * 0.6), r(hw * 0.8, hd * 0.6)]];
}

export function installFakeCanvas(engine: any) {
  if (engine.__canvas) return;
  engine.__canvas = true;
  const orig = engine.call.bind(engine);
  const locks = new Set<number>();
  let lastCommand: string | null = null;
  engine.call = async (method: string, params: any = {}) => {
    await engine.ready;
    const r = await fake(method, params ?? {});
    return r !== undefined ? r : orig(method, params);
  };
  const rec = (name: string) => engine.records?.find((r: any) => r.method === name)?.result;
  const recAll = (name: string) => (engine.records ?? []).filter((r: any) => r.method === name);
  const sel = () => engine.selection as Set<string>;
  const raw = () => engine.raw as { id: string | null; items: any[] }[];
  const selResult = () => engine.selectionResult();
  const entry = (id: any) => raw().find((r) => r.id === String(id));
  const refresh = (label: string) => { engine.snapshot(label); };
  const done = () => { engine.decode(); engine.changed("document", "selection"); };
  /** The engine's component library (canvas-palette-items.json) when recorded, else a small built-in set. */
  const comps = (): { id: string; name: string; category: string; size: number[]; item: string; shapes: V2[][] }[] => {
    const r = rec("palette.items");
    if (r?.components?.length) return r.components;
    return COMPONENTS.map((c) => ({ ...c, item: "archi-component:" + c.id, shapes: componentShapes(c.size) }));
  };
  const placed = (c: { shapes: V2[][] }, at: V2, turns: number): V2[][] => {
    const a = (((turns % 4) + 4) % 4) * (Math.PI / 2), co = Math.cos(a), si = Math.sin(a);
    return c.shapes.map((s) => s.map((q) => [at[0] + q[0] * co - q[1] * si, at[1] + q[0] * si + q[1] * co] as V2));
  };
  const pointsOf = (e: { items: any[] }): V2[] => e.items.flatMap((it: any) => (it.points ?? []).concat(it.loops ? it.loops.flat() : []).concat(it.text?.position ? [it.text.position] : []));

  async function fake(method: string, p: any): Promise<any> {
    switch (method) {
      case "command.run": { const n = String(p.line ?? "").trim().split(/\s+/)[0]; if (n) lastCommand = n.toUpperCase(); return undefined; }
      case "canvas.state": {
        const s = engine.sysvars as Record<string, string>;
        const hist = engine.history();
        const ids = [...sel()];
        return {
          ucs: { origin: [0, 0], angle: 0, world: true }, ucsIcon: { on: (Number(s.UCSICON ?? 3) & 1) !== 0, atOrigin: true }, twist: Number(s.VIEWTWIST ?? 0),
          isometric: s.SNAPSTYL === "1", isoPlane: 0, ducs: false, doubleClickEditing: true, grips: true, gripObjectLimit: 300, selectionPreview: 3,
          dynamicInput: s.DYNMODE !== "0", dynMode: 3, lastCommand, canUndo: hist.canUndo, canRedo: hist.canRedo, undoLabel: hist.undoLabel, redoLabel: hist.redoLabel,
          currentSheet: null, radialContext: ids.length ? (ids.every((i) => (engine.__elements ?? new Set()).has(i)) ? "Building elements" : "Objects") : "Drafting",
        };
      }
      case "canvas.view": return { ok: true };
      case "input.cursor": {
        const st = await orig(method, p);
        const c = engine.cmd;
        const base: V2 | null = c?.pts?.length ? c.pts[c.pts.length - 1] : null;
        const cur: V2 = Array.isArray(st.cursor) ? st.cursor : [p.x, p.y];
        if (base) {
          const dx = cur[0] - base[0], dy = cur[1] - base[1];
          let a = (Math.atan2(dy, dx) * 180) / Math.PI; if (a < 0) a += 360;
          st.dynamic = { length: Math.hypot(dx, dy), angle: a, x: dx, y: dy, relative: true, onFace: false };
          // Object snap tracking along the horizontal / vertical from the base point (OTRACK).
          const tol = 10 / Number(p.pixelsPerUnit || 0.05);
          if (!st.snap && engine.sysvars.OTRACK === "1") {
            if (Math.abs(dy) <= tol && Math.abs(dx) > tol) { const q: V2 = [cur[0], base[1]]; st.snap = { kind: "extension", point: q }; st.cursor = q; st.tracking = { points: [base], lines: [{ from: base, to: q }] }; }
            else if (Math.abs(dx) <= tol && Math.abs(dy) > tol) { const q: V2 = [base[0], cur[1]]; st.snap = { kind: "extension", point: q }; st.cursor = q; st.tracking = { points: [base], lines: [{ from: base, to: q }] }; }
            else st.tracking = { points: [base], lines: [] };
          }
        } else if (c) st.dynamic = { x: cur[0], y: cur[1], relative: false, onFace: false };
        return st;
      }
      case "grips.actions": {
        const e = entry(p.id);
        const n = e ? pointsOf(e).length : 0;
        return n > 2 ? [{ action: "stretch", title: "Stretch", immediate: false }, { action: "addVertex", title: "Add Vertex", immediate: false }, { action: "removeVertex", title: "Remove Vertex", immediate: true }] : [];
      }
      case "grips.preview": case "grips.edit": case "grips.typed": {
        const g = engine.grips().find((x: any) => String(x.id) === String(p.id) && x.index === p.index);
        if (!g) throw { code: -32602, message: `object ${p.id} has no grip ${p.index}` };
        const o: V2 = [g.x, g.y];
        let to: V2 = [Number(p.x), Number(p.y)];
        const mode = String(p.mode ?? "stretch").toLowerCase().replace(/^mo$/, "move").replace(/^ro$/, "rotate").replace(/^sc$/, "scale").replace(/^mi$/, "mirror").replace(/^st$/, "stretch");
        const ids = mode === "stretch" ? [String(p.id)] : [...new Set([...sel(), String(p.id)])];
        const ents = ids.map(entry).filter(Boolean) as { id: string; items: any[] }[];
        let ref = Number(p.reference) || 0;
        if (!ref) { let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity; for (const e of ents) for (const q of pointsOf(e)) { x0 = Math.min(x0, q[0]); y0 = Math.min(y0, q[1]); x1 = Math.max(x1, q[0]); y1 = Math.max(y1, q[1]); } ref = Math.max(Math.max(x1 - x0, y1 - y0) / 2, 1e-6); }
        if (method === "grips.typed") {
          const v = Number(p.value);
          const d = Math.hypot(to[0] - o[0], to[1] - o[1]) || 1;
          if (mode === "rotate") { const a = (v * Math.PI) / 180; to = [o[0] + Math.cos(a) * 1000, o[1] + Math.sin(a) * 1000]; }
          else if (mode === "scale") { to = [o[0] + v * ref, o[1]]; }
          else to = [o[0] + ((to[0] - o[0]) / d) * v, o[1] + ((to[1] - o[1]) / d) * v];
        }
        let f: ((q: V2) => V2) | null;
        if (mode === "stretch") {
          const turns = (((Number(p.turns) || 0) % 4) + 4) % 4, a = (turns * Math.PI) / 2;
          f = (q) => {
            let r: V2 = Math.abs(q[0] - o[0]) < 1e-6 && Math.abs(q[1] - o[1]) < 1e-6 ? [to[0], to[1]] : q;
            if (turns) { const c = Math.cos(a), s = Math.sin(a); r = [to[0] + (r[0] - to[0]) * c - (r[1] - to[1]) * s, to[1] + (r[0] - to[0]) * s + (r[1] - to[1]) * c]; }
            return r;
          };
        } else f = transformFor(mode, o, to, ref);
        if (method === "grips.preview") {
          const items: any[] = [];
          if (f) for (const e of ents) for (const it of e.items) { const c = JSON.parse(JSON.stringify(it)); mapPoints(c, f); if (c.type === "stroke") c.style = { color: PREVIEW, lineweight: 0.25, dash: [] }; items.push(c); }
          return { point: to, origin: o, snap: null, reference: ref, items };
        }
        if (!f) return { changed: [], grips: engine.grips() };
        refresh(p.action ? String(p.action).replace(/^./, (c) => c.toUpperCase()) : mode === "stretch" ? (p.copy ? "Grip Copy" : "Grip Edit") : `Grip ${mode.charAt(0).toUpperCase() + mode.slice(1)}${p.copy ? " Copy" : ""}`);
        const changed: number[] = [];
        for (const e of ents) {
          const target = p.copy ? { id: String(engine.nextId++), layer: "0", items: JSON.parse(JSON.stringify(e.items)) } : e;
          for (const it of target.items) mapPoints(it, f);
          if (p.copy) raw().push(target as any);
          changed.push(Number(target.id));
        }
        done();
        return { changed, grips: engine.grips() };
      }
      case "select.lasso": {
        const loop: V2[] = (p.points ?? []).map((q: any) => [Number(q[0]), Number(q[1])]);
        if (loop.length < 3) throw { code: -32602, message: "a lasso needs at least 3 points" };
        const crossing = p.crossing ?? signedArea(loop) > 0;
        const found: string[] = [];
        for (const e of raw()) {
          if (!e.id) continue;
          const pts = pointsOf(e);
          if (!pts.length) continue;
          const hit = crossing ? pts.some((q) => pointInPoly(q, loop)) : pts.every((q) => pointInPoly(q, loop));
          if (hit) found.push(e.id);
        }
        for (const id of found) { if (p.remove) sel().delete(id); else sel().add(id); }
        engine.changed("selection");
        return { ...selResult(), found: found.map(Number), mode: crossing ? "crossing" : "window" };
      }
      case "select.modify": {
        for (const id of p.remove ?? []) sel().delete(String(id));
        for (const id of p.add ?? []) sel().add(String(id));
        engine.changed("selection");
        return selResult();
      }
      case "pick.candidates": {
        const q: V2 = [Number(p.x), Number(p.y)], tol = Number(p.tolerance ?? 6 / (engine.ppu ?? 0.05));
        
        const c = (engine.decoded as any[]).filter((e) => e.id).map((e) => [e, distance(e, q, tol)] as [any, number]).filter(([, d]) => d <= tol).sort((a, b) => a[1] - b[1]);
        return { ids: c.map(([e]) => Number(e.id)), types: c.map(() => "line") };
      }
      case "select.chain": return { ...selResult(), chain: [], hint: "Selected 0 joined wall(s)" };
      case "select.nudge": {
        const step = (1 / (engine.ppu ?? 0.05)) * (p.big ? 10 : 1), dx = Number(p.dx ?? 0) * step, dy = Number(p.dy ?? 0) * step;
        const ids = [...sel()];
        if (!ids.length) return { moved: 0, step, hint: "Nothing to nudge (locked layer?)" };
        refresh("Nudge");
        for (const id of ids) { const e = entry(id); if (e) for (const it of e.items) mapPoints(it, (q) => [q[0] + dx, q[1] + dy]); }
        done();
        return { moved: ids.length, step, hint: `Nudged ${ids.length} object(s) by ${Math.hypot(dx, dy).toFixed(2)}` };
      }
      case "canvas.doubleClick": {
        const e = entry(p.id);
        const t = e?.items.find((it: any) => it.type === "text");
        if (t) {
          const tx = t.text ?? t;
          return { id: Number(p.id), command: `TEXTEDIT #${p.id}`, action: "textEditor", text: tx, content: String(tx.content ?? ""), singleLine: !String(tx.content ?? "").includes("\n"), styleFont: "Helvetica", format: { bold: false, italic: false, underline: false }, color: "ByLayer" };
        }
        sel().clear(); sel().add(String(p.id)); engine.changed("selection");
        return { id: Number(p.id), command: "PROPERTIES", action: "properties" };
      }
      case "text.edit": {
        const e = entry(p.id);
        const t = e?.items.find((it: any) => it.type === "text");
        if (!t) throw { code: -32000, message: `Object ${p.id} has no text to edit.` };
        refresh("Edit Text");
        (t.text ?? t).content = String(p.content);
        if (p.height) (t.text ?? t).height = Number(p.height);
        done();
        return { changed: true };
      }
      case "tempdims.get": {
        const ids = [...sel()];
        if (ids.length !== 1) return [];
        const e = (engine.decoded as any[]).find((x) => x.id === ids[0]);
        if (!e) return [];
        const mid: V2 = [(e.bounds[0] + e.bounds[2]) / 2, (e.bounds[1] + e.bounds[3]) / 2];
        let best: any = null, bd = Infinity;
        for (const o of engine.decoded as any[]) {
          if (!o.id || o.id === e.id || o.bounds[2] < mid[0] || o.bounds[0] > mid[0] || o.bounds[3] > e.bounds[1]) continue;
          const d = e.bounds[1] - o.bounds[3];
          if (d > 1e-6 && d < bd) { bd = d; best = o; }
        }
        if (!best) return [];
        return [{ id: Number(e.id), index: 0, reference: Number(best.id), from: [mid[0], best.bounds[3]], to: [mid[0], e.bounds[1]], value: bd, text: bd.toFixed(2).replace(/\.?0+$/, ""), direction: [0, 1] }];
      }
      case "tempdims.set": {
        const dims = await fake("tempdims.get", {});
        const td = dims?.[Number(p.index) || 0];
        const v = Number(p.value);
        if (!td || !(v > 0)) return { changed: false, dims };
        refresh("Temporary Dimension");
        const e = entry(td.id)!, dy = v - td.value;
        for (const it of e.items) mapPoints(it, (q) => [q[0], q[1] + dy]);
        done();
        return { changed: true, dims: await fake("tempdims.get", {}) };
      }
      case "flips.get": return [];
      case "flips.apply": return { changed: false, flips: [] };
      case "palette.items": {
        const blocks = rec("blocks.list") ?? [];
        return { blocks: (Array.isArray(blocks) ? blocks : []).map((b: any) => ({ name: b.name, item: "archi-block:" + b.name, shapes: [] })), components: comps() };
      }
      case "place.preview": {
        const c = comps().find((x) => x.item === p.item);
        const turns = Number(p.turns) || 0;
        if (!c) return { items: [], degrees: (((turns % 4) + 4) % 4) * 90 };
        return { items: placed(c, [Number(p.x), Number(p.y)], turns).map((pts) => ({ type: "stroke", points: pts, closed: false, style: { color: PREVIEW, lineweight: 0.25, dash: [] } })), degrees: (((turns % 4) + 4) % 4) * 90 };
      }
      case "place.drop": {
        const s = String(p.item ?? "");
        if (s.startsWith("archi-command:")) { const prompt = await orig("command.run", { line: s.slice("archi-command:".length), cancel: true }); return { ok: true, prompt, selection: [...sel()].map(Number) }; }
        const c = comps().find((x) => x.item === s);
        if (!c) return { ok: false, selection: [...sel()].map(Number) };
        refresh(`Place ${c.name}`);
        const id = String(engine.nextId++);
        (engine.__elements ??= new Set()).add(id);
        raw().push({ id, layer: "A-ELEMENTS", items: placed(c, [Number(p.x), Number(p.y)], Number(p.turns) || 0).map((pts) => ({ type: "stroke", points: pts, closed: false, style: { color: "#d8c9b0", lineweight: 0.18, dash: [] } })) } as any);
        sel().clear(); sel().add(id);
        engine.log(`Placed ${c.name.toLowerCase()} at ${Number(p.x).toFixed(2)},${Number(p.y).toFixed(2)}.`);
        done();
        return { ok: true, id: Number(id), selection: [Number(id)] };
      }
      case "file.drop": {
        const paths: string[] = p.paths ?? [];
        const open = paths.filter((x) => /\.(archi|archiz|archit)$/i.test(x));
        const scripts = paths.filter((x) => /\.(scr|js|lsp|py)$/i.test(x));
        const rest = paths.filter((x) => !open.includes(x) && !scripts.includes(x));
        for (const f of rest) engine.log(`${f.split(/[\\/]/).pop()}: import needs archi-engine (fixture mode).`);
        return { open, scripts, unsupported: [], ids: [] };
      }
      case "sheet.viewports": {
        const dl = recAll("view.drawList").find((r: any) => r.params?.layout !== undefined)?.result;
        const vps = (dl?.viewports ?? []).map((v: any) => ({ ...v, locked: locks.has(v.index), ratioText: v.ratio ? `1:${Math.round(v.ratio)}` : "" }));
        return { layout: dl?.layout ?? "Sheet 1", index: 0, paper: dl?.paper, grid: 0, viewports: vps };
      }
      case "sheet.viewport": {
        const dl = recAll("view.drawList").find((r: any) => r.params?.layout !== undefined)?.result;
        const vp = dl?.viewports?.find((v: any) => v.index === p.index);
        if (!vp) throw { code: -32602, message: "missing or unknown viewport 'index'" };
        const op = String(p.op).toLowerCase();
        if (locks.has(vp.index) && ["move", "remove", "scale", "removeclip", "clip", "center"].includes(op)) { engine.log("The viewport is locked (VPLOCK Off to unlock)."); throw { code: -32000, message: "The viewport is locked (VPLOCK Off to unlock)." }; }
        if (op === "lock") locks.add(vp.index); else if (op === "unlock") locks.delete(vp.index);
        else if (op === "move") {
          const dx = Number(p.origin[0]) - vp.rect[0], dy = Number(p.origin[1]) - vp.rect[1];
          const old = vp.rect.join(",");
          vp.rect = [vp.rect[0] + dx, vp.rect[1] + dy, vp.rect[2] + dx, vp.rect[3] + dy];
          for (const it of dl.items ?? []) if (Array.isArray(it.clip) && it.clip.join(",") === old) { mapPoints(it, (q) => [q[0] + dx, q[1] + dy]); it.clip = vp.rect; }
          engine.snapshot("Move Viewport");
        } else if (op === "remove") {
          const old = vp.rect.join(",");
          dl.items = (dl.items ?? []).filter((it: any) => !(Array.isArray(it.clip) && it.clip.join(",") === old));
          dl.viewports = dl.viewports.filter((v: any) => v !== vp);
          engine.snapshot("Remove Viewport");
        }
        engine.changed("document");
        return fake("sheet.viewports", {});
      }
    }
    return undefined;
  }
}
