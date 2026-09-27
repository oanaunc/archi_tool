# 3D view and photographic renderer (Windows shell)

WebGL 2 port of the Mac 3D viewport and renderer (`ArchiApp/Viewport3DView.swift`, `Viewport3DExtras.swift`,
`Navigation3DPlus.swift`, `RenderController.swift`, `BeautyLighting.swift`, `BeautyRender.swift`, `SketchyStyle.swift`).
No dependencies: three.js could not be installed here (npm registry blocked), and a small renderer written for this
job reproduces SceneKit's behaviour more closely than three.js's defaults would.

## Mounting

```ts
import { View3D, EngineBridge } from "./view3d";
const view = new View3D(container, {
  resolveAsset: (p) => archi.fileUrl(join(drawingFolder, p)),   // "textures/cedar.jpg" → file URL
  icon: (sf, size) => icon(sf, size),                            // the shell's SF Symbol → Lucide icons
});
const bridge = new EngineBridge(view, engine, { print: (t) => app.print(t), savePNG });
await bridge.load();              // model.meshes + render.settings (+ view3d.info when the engine has it)
// RENDERSAVE: await bridge.renderSave("Goldenhour Front 1920 1080 out.png")
```

`EngineBridge` reloads on `changed` notifications, syncs the selection both ways (`select.get` / `select.set`) and
handles the `archi:host` events the shell re-dispatches (`setViewStyle`, `setView`, `walkthrough`, `render`).

## What is replicated

- **Scene**: model.meshes (base64 or `binary` buffer file), model mm → metres, Z up; feature edges nudged 2 mm
  outward; textures with the SceneKit multiply tint (colour 75 % towards white), normal and roughness maps
  (MATMAPS, or `<name>_n` / `<name>_r` beside the texture), derived normal maps for other textures; missing UVs are
  generated (box, spherical for foliage).
- **Visual styles**: Wireframe, Hidden Line, Shaded, Shaded with Edges, Conceptual, Realistic, X-Ray, Sketchy
  (hand-drawn strokes with the Mac's deterministic noise), with the Mac's backgrounds, ground grid and edge colours.
- **Lighting presets** Daylight / Golden hour / Overcast / Night with the numbers of `BeautyPreset.look`: sun
  direction, colour and intensity, procedural HDR sky (same noise, clouds, sun glow, stars, moon halo, town glow)
  as background and image-based light, horizon haze, meadow ground, deferred-style soft shadows (shadow alpha
  darkens the whole pixel, as SceneKit's deferred shadow pass does), exposure, white point, bloom, saturation,
  contrast, SSAO, vignette, tinted reflective glass, lit windows (windowGlow), emissive lamps (lampGlow), placed
  lights and fixtures scaled by `artificial`, leaf lumps and leaf cut-outs.
- **Navigation**: turntable orbit 0.01 rad per point with inertia, right / middle / Shift-drag pan, wheel dolly,
  double-click to re-centre, standard views and SW/SE/NE/NW iso with the Mac framing, view cube (faces, edges,
  corners), orthographic toggle, two-point perspective, walk (collisions, floors, stairs, gravity) / fly / look.
- **Overlay**: the Mac pill bar, view cube, section box panel (six sliders, Selection / Level / Reset), sun study,
  clipping plane, saved cameras menu, visual style menu, walk hint.
- **Renders**: `renderToPNG` / `renderPixels` — saved camera with vertical correction (pitch ≤ 20°), 4× MSAA plus
  supersampling (3× up to 1920×1080, else 2×, frame ≤ 12 288 px) filtered down; final quality shadow map 8192 and
  2048-wide sky.

Calibration constants (`Renderer.SCENE_SCALE`, `SUN_SCALE`, `ENV_DIFFUSE`, `LIGHT_SCALE`) map SceneKit's units to
this shader; they were measured against the Mac renders in `build/renders` (see `windows/test/view3d`).

## Tests

`node windows/test/view3d/run.mjs` renders every preset from the saved cameras and writes side-by-side comparisons;
`node windows/test/view3d/ui.mjs` drives the interactive view (styles, orbit, pan, zoom, view cube, picking, section
box, walk, render to PNG). Both run in headless Chromium (SwiftShader is enough).
