// The user guide is bundled as text (build.mjs: esbuild loader ".md": "text").
declare module "*.md" { const text: string; export default text; }
