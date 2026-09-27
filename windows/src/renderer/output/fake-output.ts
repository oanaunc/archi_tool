// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Fixture-engine side of the output methods (docs/ENGINE-PROTOCOL.md "Output"): the recorded Cedar House answers
// (output-*.json: plot dialog targets, the sheet A-102 and model previews, plot style tables, render window data,
// camera paths and sun frames) and a small simulation of the rest (PDF files, publishing, path tracer passes), so the
// output windows can be exercised in the browser test page. The output commands answer with their host actions.
// Never used inside the Electron app.

const COMMANDS: { name: string; aliases: string[]; category: string; summary: string }[] = [
  { name: "PREVIEW", aliases: ["PRE", "PRINTPREVIEW", "PLOTPREVIEW", "PLOTDIALOG"], category: "Output", summary: "Plot dialog with a live preview: prints or saves exactly what is shown." },
  { name: "PUBLISH", aliases: ["BATCHPLOT", "EXPORTSHEETS", "PUBLISHPDF"], category: "Output", summary: "Publishes all sheets to one multi-page PDF (PUBLISH path.pdf, or Enter for a dialog)." },
  { name: "BATCHPUBLISH", aliases: ["PUBLISHSET", "BATCHPLOTPDF"], category: "Output", summary: "Publishes chosen sheets to one PDF with bookmarks (sheet number and name) and optional sheet index." },
  { name: "PLOTSTYLE", aliases: ["CTB", "PLOTSTYLES", "STYLESMANAGER"], category: "Output", summary: "Plot style tables (colour → pen colour, lineweight, screening): Edit, Set for the sheet/model, List." },
  { name: "PRINTSETUP", aliases: ["PRINTOPTIONS", "QUICKPRINT"], category: "Output", summary: "Prints with printer, paper, tray (input slot), media, scaling (fit, 1:1, percent) and copies." },
  { name: "RENDERQUEUE", aliases: ["BATCHRENDER", "RENDERHISTORY"], category: "View", summary: "Render queue: add the current view or saved cameras, render them in turn to PNG files; render history with thumbnails." },
  { name: "CAMERAPATHEDIT", aliases: ["ANIMPATH", "CAMPATHS"], category: "View", summary: "Camera path editor: keys from the 3D view or saved cameras at times, timeline scrubbing and playback, video export." },
  { name: "PATHTRACE", aliases: ["PTRENDER", "RENDERPT", "PATHTRACER", "RAYTRACE"], category: "View", summary: "Progressive path-traced render of the 3D view (GGX materials, glass refraction, PBR maps, sun, sky, lights): Window, or File with size, samples and denoising." },
];

const st = { paths: [] as any[], pt: { samples: 0, target: 0, running: false, w: 0, h: 0, t0: 0 }, styles: [] as any[] };

function rec(fe: any, method: string, pred: (p: any) => boolean = () => true) {
  return (fe.records as any[]).find((r) => r.method === method && pred(r.params ?? {}))?.result;
}
function gradient(w: number, h: number, k: number): string {
  const c = document.createElement("canvas"); c.width = w; c.height = h;
  const g = c.getContext("2d")!;
  const gr = g.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, "#6f8fbf"); gr.addColorStop(0.55, "#d9e2ee"); gr.addColorStop(0.56, "#7a8a5a"); gr.addColorStop(1, "#4d5a35");
  g.fillStyle = gr; g.fillRect(0, 0, w, h);
  g.fillStyle = `rgba(210,190,160,${Math.min(1, 0.3 + k / 10)})`; g.fillRect(w * 0.3, h * 0.35, w * 0.4, h * 0.3);
  return c.toDataURL("image/png");
}

export function fakeOutputCall(fe: any, method: string, p: any): any {
  const emitHost = (params: any) => fe.emit("host", params);
  const idle = () => ({ active: false, message: "Command:", keywords: [], kinds: [], preview: [] });
  switch (method) {
    case "engine.hello": {
      const h = fe.hello;
      if (h && Array.isArray(h.commands)) for (const c of COMMANDS) if (!h.commands.some((x: any) => x.name === c.name)) h.commands.push({ ...c, modifies: false });
      return undefined;
    }
    case "command.run": {
      const toks = String(p.line ?? "").trim().split(/\s+/);
      const name = toks[0]?.toUpperCase() ?? "";
      const def = COMMANDS.find((c) => c.name === name || c.aliases.includes(name));
      if (name === "RENDER" || name === "RR") { fe.log("Command: RENDER"); emitHost({ action: "render" }); return idle(); }
      if (name === "PLOT" && toks.length === 1) { fe.log("Command: PLOT"); emitHost({ action: "plot" }); return idle(); }
      if (!def) return undefined;
      fe.log(`Command: ${name}`);
      const arg = toks.slice(1).join(" ");
      switch (def.name) {
        case "PREVIEW": emitHost({ action: "dialog", dialog: "plotPreview" }); break;
        case "PRINTSETUP": emitHost({ action: "dialog", dialog: "printSetup" }); break;
        case "PUBLISH": emitHost({ action: "output", op: "publish", suggested: "Cedar House — sheets.pdf", bookmarks: true }); break;
        case "BATCHPUBLISH": emitHost({ action: "dialog", dialog: "batchPublish" }); break;
        case "PLOTSTYLE": if (!arg || /^e/i.test(arg)) emitHost({ action: "dialog", dialog: "plotStyles" }); break;
        case "RENDERQUEUE": {
          const cams = rec(fe, "camerapath.list")?.cameras ?? [];
          const add = /^c/i.test(arg) ? cams.map((c: any) => ({ name: `Cedar House – ${c.name}`, camera: c })) : [];
          if (add.length) fe.log(`Queued ${add.length} saved camera(s).`);
          emitHost({ action: "dialog", dialog: "renderQueue", add, run: /^r/i.test(arg) });
          break;
        }
        case "CAMERAPATHEDIT": emitHost({ action: "dialog", dialog: "cameraPaths" }); break;
        case "PATHTRACE": emitHost({ action: "dialog", dialog: "pathTrace", start: true }); break;
      }
      return idle();
    }
    case "plot.info": return rec(fe, "plot.info") ?? { what: [{ value: "model", title: "Model — Ground Floor" }], default: "model", sheets: [], title: "Plot Preview", sheetNote: "" };
    case "plot.preview": {
      const w = String(p.what ?? "model");
      const r = w.startsWith("sheet") ? rec(fe, "plot.preview", (q) => String(q.what ?? "").startsWith("sheet")) : rec(fe, "plot.preview", (q) => q.what === "model");
      if (!r) throw { code: -32000, message: "No recorded plot preview." };
      const mono = p.setup?.colorMode === "Monochrome";
      const pages = r.pages.map((pg: any) => ({ ...pg, svg: mono ? String(pg.svg).replace(/(stroke|fill)="#(?!ffffff)[0-9a-f]{6}"/g, '$1="#000000"') : pg.svg }));
      return { ...r, pages, pdf: `C:\\Temp\\ArchiPlot-${Date.now()}.pdf`, what: w };
    }
    case "plot.pdf": { if (p.quiet !== true) fe.log(`Plotted to ${p.path}`); return { path: p.path, bytes: 1000, pages: 1, layers: [], links: 0 }; }
    case "plot.publish": {
      const sheets = rec(fe, "plot.info")?.sheets ?? [];
      const list = p.layouts ? sheets.filter((s: any) => p.layouts.includes(s.index)) : sheets;
      fe.log(`Published ${list.length} sheet(s)${p.layouts ? (p.bookmarks !== false ? " with bookmarks" : "") : ""} to ${p.path}`);
      return { path: p.path, pages: list.length, bytes: 1000, skipped: 0, bookmarks: p.bookmarks !== false ? list.map((s: any) => s.bookmark) : [] };
    }
    case "plot.sheetSVG": fe.log(`Wrote ${p.path}`); return { files: [p.path] };
    case "plotstyle.list": {
      const r = rec(fe, "plotstyle.list");
      if (!r) return undefined;
      return { ...r, tables: [...r.tables, ...st.styles] };
    }
    case "plotstyle.save": {
      let name = String(p.table?.name ?? "").trim();
      if (!/\.ctb$/i.test(name)) name += ".ctb";
      st.styles = st.styles.filter((t) => t.name.toLowerCase() !== name.toLowerCase());
      st.styles.push({ name, pens: p.table.pens, count: Object.keys(p.table.pens ?? {}).length, builtIn: false });
      fe.log(`Plot style table ${name} saved in the drawing. Choose it in Page Setup (or PLOTSTYLE Set).`);
      return { name, list: fakeOutputCall(fe, "plotstyle.list", {}) };
    }
    case "plotlog.get": return { path: "Plot Log.csv", columns: ["Date", "Drawing", "Output", "Sheets", "Plot style", "File"], rows: [] };
    case "render.window": return rec(fe, "render.window");
    case "camerapath.list": { const r = rec(fe, "camerapath.list"); return r ? { ...r, paths: st.paths } : undefined; }
    case "camerapath.set": st.paths = (p.paths ?? []).map((x: any) => ({ ...x, duration: Math.max(0, ...(x.keys ?? []).map((k: any) => k.time)) })); fe.snapshot?.(p.label ?? "Camera Paths"); return fakeOutputCall(fe, "camerapath.list", {});
    case "camerapath.frames": {
      const r = rec(fe, "camerapath.frames");
      if (p.path) {
        const path = st.paths.find((x) => x.name === p.path);
        if (!path) throw { code: -32602, message: `no camera path '${p.path}'` };
        const n = Math.max(2, Math.floor(path.duration * path.fps) + 1), keys = [...path.keys].sort((a: any, b: any) => a.time - b.time);
        return { fps: path.fps, count: n, frames: Array.from({ length: n }, (_, i) => keys[Math.min(keys.length - 1, Math.floor((i / (n - 1)) * (keys.length - 1)))].camera) };
      }
      const n = Math.max(2, Math.round((p.seconds ?? 10) * (p.fps ?? 30)));
      const f = r?.frames ?? [];
      return { fps: p.fps ?? 30, count: n, frames: Array.from({ length: n }, (_, i) => f[Math.min(f.length - 1, Math.floor((i / (n - 1)) * (f.length - 1)))]) };
    }
    case "render.sunFrames": {
      const r = rec(fe, "render.sunFrames");
      const n = Math.max(2, Math.round((p.seconds ?? 10) * (p.fps ?? 30)));
      const f = r?.frames ?? [];
      return { fps: p.fps ?? 30, frames: Array.from({ length: n }, (_, i) => f[Math.min(f.length - 1, Math.floor((i / (n - 1)) * (f.length - 1)))]) };
    }
    case "render.queueName": return { file: String(p.name ?? "Render").replace(/[\\/:?*"<>|]/g, "-") + ".png" };
    case "render.pass": return { width: p.width, height: p.height, image: gradient(Math.min(p.width, 320), Math.min(p.height, 180), 5), ...(String(p.pass).startsWith("Material") ? { materials: [{ name: "Limestone", color: "#f23c3c" }] } : {}) };
    case "pathtrace.start": st.pt = { samples: 0, target: p.samples ?? 64, running: true, w: p.width ?? 960, h: p.height ?? 540, t0: performance.now() }; return { triangles: 1234, lights: 2, textures: 6, width: st.pt.w, height: st.pt.h, target: st.pt.target, status: "1234 triangles, 2 lights" };
    case "pathtrace.status": {
      if (st.pt.running) { st.pt.samples = Math.min(st.pt.target, st.pt.samples + 8); if (st.pt.samples >= st.pt.target) st.pt.running = false; }
      const secs = (performance.now() - st.pt.t0) / 1000;
      return { running: st.pt.running, samples: st.pt.samples, target: st.pt.target, seconds: secs, width: st.pt.w, height: st.pt.h, status: `${st.pt.samples} samples · ${secs.toFixed(1)} s · 1234 triangles`, image: st.pt.samples > 0 ? gradient(Math.min(st.pt.w, 320), Math.min(st.pt.h, 180), st.pt.samples) : undefined };
    }
    case "pathtrace.stop": st.pt.running = false; return { stopped: true };
    case "pathtrace.mix": return { sun: p.sun ?? 1, sky: p.sky ?? 1, artificial: p.artificial ?? 1 };
    case "pathtrace.save": return { path: p.path };
    case "plot.shadePlotImage": return { key: "SHADEPLOTIMAGE", path: p.path };
  }
  return undefined;
}
