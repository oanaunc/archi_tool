# 3D view and photographic renderer (Windows shell)

WebGL 2 port of the Mac 3D viewport and renderer (`ArchiApp/Viewport3DView.swift`, `Viewport3DExtras.swift`,
`Viewport3DTools.swift`, `Studio3D.swift`, `Navigation3DPlus.swift`, `SceneExtras.swift`, `SceneEffects.swift`,
`StereoPanorama.swift`, `RenderController.swift`, `BeautyLighting.swift`, `BeautyRender.swift`, `SketchyStyle.swift`).
No dependencies: three.js could not be installed here (npm registry blocked), and a small renderer written for this
job reproduces SceneKit's behaviour more closely than three.js's defaults would.

## Mounting

```ts
import { View3D, EngineBridge } from "./view3d";
const view = new View3D(container, {
  resolveAsset: (p) => archi.fileUrl(join(drawingFolder, p)),   // "textures/cedar.jpg" → file URL
  icon: (sf, size) => icon(sf, size),                            // the shell's SF Symbol → Lucide icons
});
const bridge = new EngineBridge(view, engine, {
  print: (t) => app.print(t),
  readBinary: (p) => fetch(archi.fileUrl(p)).then((r) => r.arrayBuffer()),   // model.meshes {"binary": true}
  chooseSavePath: (s) => archi.saveFileDialog({ defaultPath: s }),            // panoramas / VIEWIMAGE without a path
});
await bridge.load();              // model.meshes (one temporary .bin, full detail) + render.settings + view3d.info
// RENDERSAVE: await bridge.renderSave("Goldenhour Front 1920 1080 out.png")
```

`EngineBridge` reloads on `changed` notifications (3D view variables it set itself only refresh `view3d.info`), syncs the
selection both ways (`select.get` / `select.set`), reports the camera (`view3d.setCamera`), stores SECTIONBOX /
SECTIONPLANE / PERSPECTIVE / SUNSTUDY / VSCURRENT (`view3d.setVariable`), fetches the section caps
(`view3d.sectionCaps`), commits gizmo drags (`view3d.transform`), saves and deletes cameras, and handles the `host`
actions of 3D commands (`setViewStyle`, `setView`, `walkthrough`, `render` and `{"action":"view3d","op":…}`: gizmo,
measure, levels, sectionBoxPanel, sunStudy, orbitSelection, camera, fov, navigate, positionCamera, twoPoint, wheel,
animate, animationFrame, panorama, viewImage). Images are written by the engine (`view3d.saveImage`).

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

- **Render window extras** (`FrameOptions`): clay model (RenderEngine.applyClay: matte white 0.92, roughness 0.85, glass
  keeps its transparency, +10 % environment with a preset), depth of field (SCNCamera focusDistance / fStop, 24 mm sensor:
  a circle-of-confusion gather on the HDR frame before the camera response), environment images (`envImage`: HDRI File —
  Radiance .hdr flat or RLE, JPEG, PNG — decoded by `hdri.ts` into the sky's equirect layout as image-based light and
  background).
- **Lights**: point, spot (inner 70 % of the beam), area and line (Lambertian emitters) and IES (the photometric web's
  relative intensity by angle from `model.meshes` `iesProfile`, a 32 × 16 half-float table), SceneKit attenuation.
- **Billboards** (`billboards.ts`, BILLBOARD): person / tree / shrub drawn as on the Mac or an image file, cut out by alpha,
  turned about the vertical towards the camera every frame (shadows follow). **Ambient occlusion** of the drawing
  (AODIALOG: `view3d.info.ambientOcclusion.viewport`) overrides the style's SSAO like AOForm.viewport.

Calibration constants (`Renderer.SCENE_SCALE`, `SUN_SCALE`, `ENV_DIFFUSE`, `LIGHT_SCALE`) map SceneKit's units to
this shader; they were measured against the Mac renders in `build/renders` (see `windows/test/view3d`). SSAO darkens
only the indirect light (`AO_INDIRECT`, a second colour attachment of the scene pass), and the sun shadow uses a
slope-scaled bias over the soft-shadow kernel (`SLOPE_TEXELS`) so grazing sun (golden hour) does not self-shadow the
ground. `node windows/test/view3d/calib.mjs '[{"name":"x","statics":{"SUN_SCALE":0.9}}]' --full` prints region means
(limestone, cedar, sky, paving, grass) next to the Mac's for each preset; `run.mjs --full` compares the full-detail
model (`build/engine-fixtures/view3d-meshes-lod0.bin`, written by `./scripts/q.sh engine`).

- **Tools** (`extras.ts`, `effects.ts`): the bottom tool bar (ruler + Off / Move / Rotate / Scale), the gizmo drawn over the
  model (X/Y/Z arrows in the macOS system colours, purple ring, white scale handle) with the Mac drag maths (axis delta
  from the projected axis, screen sweep, Shift snaps 15° / 0.1, grid snap) and a live preview; 3D measuring (accent
  markers, "Distance · ΔX · ΔY · ΔZ · plan"); levels in 3D (isolate, explode by 1.5 / 3 / 6 m) and field of view; the
  saved-cameras menu with the Save Camera sheet and Delete; the clipping plane panel (Horizontal / Along X / Along Y,
  Flip, Level, Remove) with red cap faces; the sun study panel (day, time, play, Mar 21 … Dec 21, NOAA sun at the site);
  the steering wheel (Zoom, Pan, Orbit, Rewind, Center, Walk, Up/Down, Look); door leaves split from the frame and swung
  about their hinge, object animations played in a loop; weather (snow cover on up-facing faces, wet surfaces, haze,
  rain streaks and snow flakes), seasons (vegetation tint), water waves; two-point perspective; VIEWIMAGE (current
  style, transparent PNG / JPEG / TIFF) and PANORAMA / STEREOPANORAMA (cube faces → equirectangular, omni-directional
  stereo over-under).

## Tests

`node windows/test/view3d/render-match.mjs --full --tag after` renders Front / Corner / Aerial × the four presets and writes
the per-region (sky, lawn, paving, cedar, limestone, glass; `regions.py`) mean-colour differences to the Mac renders with
side-by-side images (`test-results/render-match/<tag>/`); `calib-regions.mjs` sweeps renderer constants over the same regions;
`render-extras.mjs` checks clay, depth of field, HDRI, billboards and IES lights.
`node windows/test/view3d/run.mjs` renders every preset from the saved cameras and writes side-by-side comparisons;
`node windows/test/view3d/ui.mjs` drives the interactive view (styles, orbit, pan, zoom, view cube, picking, section
box, walk, render to PNG); `node windows/test/view3d/tools.mjs` checks the tools above and the bridge's view3d actions.
All run in headless Chromium (SwiftShader is enough).
