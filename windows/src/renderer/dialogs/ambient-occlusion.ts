// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Ambient Occlusion (AODIALOG; ArchiApp/AppRound12Panels.swift AOPanel / AOForm): intensity 0–2, radius in drawing
// units, rays per point 4–256 in steps of 4; Off and Apply write AOINTENSITY / AORADIUS / AOSAMPLES in one "Ambient
// Occlusion" undo step (render.aoSet), and the 3D view picks the occlusion up from view3d.info.
import { h } from "../dom";
import { toolWindow, slider, numberField, stepper, flatButton, row, label, spacer, fmtNumber } from "./ui";
import { app } from "./context";

interface AOInfo { intensity: number; radius: number; samples: number; units: string; on: boolean }

export async function openAmbientOcclusion(initial?: AOInfo) {
  const a = app();
  const info: AOInfo | null = initial ?? await a.tryCall("render.ao", {});
  if (!info) { a.print("Ambient occlusion needs archi-engine."); return; }
  const f = { intensity: info.intensity, radius: info.radius, samples: info.samples };
  toolWindow("ambientOcclusion", "Ambient Occlusion", 420, 220, (body) => {
    body.style.padding = "12px";
    body.style.display = "flex"; body.style.flexDirection = "column"; body.style.gap = "8px";
    const value = label(f.intensity.toFixed(2), { width: 36 });
    const intensity = slider(0, 2, 0.01, f.intensity, (v) => { f.intensity = v; value.textContent = v.toFixed(2); }, 220);
    const message = label("", { dim: true });
    const apply = async () => {
      const r = await a.tryCall("render.aoSet", { intensity: f.intensity, radius: f.radius, samples: f.samples });
      message.textContent = r?.message ?? "";
      await a.refresh(["document", "drawing"]);
    };
    body.append(
      h("div", { class: "dnote", text: "Darkens corners, reveals and overhangs in the 3D viewport, renders, shaded elevations, sections and their PDF/SVG exports." }),
      row(label("Intensity", { width: 80 }), intensity, value),
      row(label("Radius", { width: 80 }), numberField(f.radius, (v) => { f.radius = v; }, { width: 90, positive: true }), label(info.units)),
      stepper((v) => `Rays per point: ${v}`, f.samples, 4, 256, (v) => { f.samples = v; }, { step: 4 }),
      row(message, spacer(), flatButton("Off", () => { f.intensity = 0; intensity.value = "0"; value.textContent = "0.00"; void apply(); }),
        flatButton("Apply", () => void apply(), { prominent: true })),
    );
    void fmtNumber;
  });
}
