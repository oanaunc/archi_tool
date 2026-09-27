// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// 3D view and photographic renderer of the Windows shell (WebGL 2, no dependencies). See README.md in this folder.
export { View3D, encodeImage } from "./view3d";
export type { View3DOptions, RenderRequest, NavMode, View3DInfo } from "./view3d";
export { View3DExtras } from "./extras";
export type { ExtrasHost, TransformRequest } from "./extras";
export * as Effects from "./effects";
export { Renderer, UNIT } from "./renderer";
export type { FrameOptions, SectionBox, SectionPlane } from "./renderer";
export { SceneModel } from "./scene";
export type { MeshesResult, EngineMesh, EngineLight, MaterialMaps, SavedCamera } from "./scene";
export { PRESETS, PRESET_NAMES, PRESET_KEYWORDS, VISUAL_STYLES, presetNamed, lookFrom, styleNamed, sunDirection } from "./look";
export type { Look, VisualStyle } from "./look";
export type { CameraState } from "./camera";
export { parseSectionBox, formatSectionBox, parseSectionPlane, formatSectionPlane } from "./variables";
export { EngineBridge } from "./engine-bridge";
export type { EngineLike, BridgeOptions, View3DDocument } from "./engine-bridge";
