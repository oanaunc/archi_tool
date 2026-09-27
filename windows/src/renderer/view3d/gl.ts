// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Thin WebGL2 helpers: programs, textures and render targets.

export type GL = WebGL2RenderingContext;

export class Program {
  readonly prog: WebGLProgram;
  private locs = new Map<string, WebGLUniformLocation | null>();
  constructor(readonly gl: GL, vs: string, fs: string, readonly name = "program") {
    const p = gl.createProgram()!;
    const sh = (type: number, src: string) => {
      const s = gl.createShader(type)!;
      gl.shaderSource(s, src);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
        const log = gl.getShaderInfoLog(s);
        const lines = src.split("\n").map((l, i) => `${i + 1}: ${l}`).join("\n");
        throw new Error(`${name}: shader compile failed: ${log}\n${lines}`);
      }
      return s;
    };
    gl.attachShader(p, sh(gl.VERTEX_SHADER, vs));
    gl.attachShader(p, sh(gl.FRAGMENT_SHADER, fs));
    gl.bindAttribLocation(p, 0, "aPos");
    gl.bindAttribLocation(p, 1, "aNormal");
    gl.bindAttribLocation(p, 2, "aUV");
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(`${name}: link failed: ${gl.getProgramInfoLog(p)}`);
    this.prog = p;
  }
  use() { this.gl.useProgram(this.prog); return this; }
  loc(n: string) {
    if (!this.locs.has(n)) this.locs.set(n, this.gl.getUniformLocation(this.prog, n));
    return this.locs.get(n)!;
  }
  f(n: string, ...v: number[]) {
    const l = this.loc(n); if (!l) return this;
    const g = this.gl;
    if (v.length === 1) g.uniform1f(l, v[0]); else if (v.length === 2) g.uniform2f(l, v[0], v[1]);
    else if (v.length === 3) g.uniform3f(l, v[0], v[1], v[2]); else g.uniform4f(l, v[0], v[1], v[2], v[3]);
    return this;
  }
  i(n: string, v: number) { const l = this.loc(n); if (l) this.gl.uniform1i(l, v); return this; }
  v3(n: string, v: ArrayLike<number>) { const l = this.loc(n); if (l) this.gl.uniform3f(l, v[0], v[1], v[2]); return this; }
  v3a(n: string, v: Float32Array) { const l = this.loc(n); if (l) this.gl.uniform3fv(l, v); return this; }
  v4a(n: string, v: Float32Array) { const l = this.loc(n); if (l) this.gl.uniform4fv(l, v); return this; }
  m4(n: string, m: Float32Array) { const l = this.loc(n); if (l) this.gl.uniformMatrix4fv(l, false, m); return this; }
  tex(n: string, unit: number, t: WebGLTexture | null, target: number = WebGL2RenderingContext.TEXTURE_2D) {
    const g = this.gl;
    g.activeTexture(g.TEXTURE0 + unit);
    g.bindTexture(target, t);
    this.i(n, unit);
    return this;
  }
}

export interface Target {
  fb: WebGLFramebuffer; width: number; height: number;
  color?: WebGLTexture; depth?: WebGLTexture;
  /** Second colour attachment (the indirect light of the scene pass). */
  color2?: WebGLTexture;
  /** Multisampled render buffers (resolved into `color` / `depth` of `resolve`). */
  msColor?: WebGLRenderbuffer; msDepth?: WebGLRenderbuffer; msColor2?: WebGLRenderbuffer;
}

export function texture2D(gl: GL, w: number, h: number, internal: number, format: number, type: number,
  data: ArrayBufferView | null = null, filter: number = gl.LINEAR, wrap: number = gl.CLAMP_TO_EDGE): WebGLTexture {
  const t = gl.createTexture()!;
  gl.bindTexture(gl.TEXTURE_2D, t);
  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  gl.texImage2D(gl.TEXTURE_2D, 0, internal, w, h, 0, format, type, data);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter === gl.LINEAR_MIPMAP_LINEAR ? gl.LINEAR : filter);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap);
  return t;
}

/** Colour target (RGBA16F by default) with an optional depth texture. */
export function target(gl: GL, w: number, h: number, opts: { hdr?: boolean; depth?: boolean; filter?: number; mrt?: boolean } = {}): Target {
  const fb = gl.createFramebuffer()!;
  gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
  const hdr = opts.hdr ?? true;
  const color = texture2D(gl, w, h, hdr ? gl.RGBA16F : gl.RGBA8, gl.RGBA, hdr ? gl.HALF_FLOAT : gl.UNSIGNED_BYTE, null, opts.filter ?? gl.LINEAR);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, color, 0);
  let depth: WebGLTexture | undefined;
  if (opts.depth) {
    depth = texture2D(gl, w, h, gl.DEPTH_COMPONENT24, gl.DEPTH_COMPONENT, gl.UNSIGNED_INT, null, gl.NEAREST);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, depth, 0);
  }
  let color2: WebGLTexture | undefined;
  if (opts.mrt) {
    color2 = texture2D(gl, w, h, gl.RGBA16F, gl.RGBA, gl.HALF_FLOAT, null, opts.filter ?? gl.LINEAR);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT1, gl.TEXTURE_2D, color2, 0);
    gl.drawBuffers([gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1]);
  }
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  return { fb, width: w, height: h, color, depth, color2 };
}

/** Multisampled HDR colour + depth render buffers. */
export function msTarget(gl: GL, w: number, h: number, samples: number, mrt = false): Target {
  const fb = gl.createFramebuffer()!;
  gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
  const msColor = gl.createRenderbuffer()!;
  gl.bindRenderbuffer(gl.RENDERBUFFER, msColor);
  gl.renderbufferStorageMultisample(gl.RENDERBUFFER, samples, gl.RGBA16F, w, h);
  gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, msColor);
  const msDepth = gl.createRenderbuffer()!;
  gl.bindRenderbuffer(gl.RENDERBUFFER, msDepth);
  gl.renderbufferStorageMultisample(gl.RENDERBUFFER, samples, gl.DEPTH_COMPONENT24, w, h);
  gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, msDepth);
  let msColor2: WebGLRenderbuffer | undefined;
  if (mrt) {
    msColor2 = gl.createRenderbuffer()!;
    gl.bindRenderbuffer(gl.RENDERBUFFER, msColor2);
    gl.renderbufferStorageMultisample(gl.RENDERBUFFER, samples, gl.RGBA16F, w, h);
    gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT1, gl.RENDERBUFFER, msColor2);
    gl.drawBuffers([gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1]);
  }
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  return { fb, width: w, height: h, msColor, msDepth, msColor2 };
}

export function depthTarget(gl: GL, size: number): Target {
  const fb = gl.createFramebuffer()!;
  gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
  const depth = texture2D(gl, size, size, gl.DEPTH_COMPONENT24, gl.DEPTH_COMPONENT, gl.UNSIGNED_INT, null, gl.NEAREST);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, depth, 0);
  gl.drawBuffers([gl.NONE]);
  gl.readBuffer(gl.NONE);
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  return { fb, width: size, height: size, depth };
}

export function disposeTarget(gl: GL, t: Target | null | undefined) {
  if (!t) return;
  if (t.color) gl.deleteTexture(t.color);
  if (t.color2) gl.deleteTexture(t.color2);
  if (t.msColor2) gl.deleteRenderbuffer(t.msColor2);
  if (t.depth) gl.deleteTexture(t.depth);
  if (t.msColor) gl.deleteRenderbuffer(t.msColor);
  if (t.msDepth) gl.deleteRenderbuffer(t.msDepth);
  gl.deleteFramebuffer(t.fb);
}

/** RGBA8 texture from an image, sRGB decoded by the GPU when `srgb`, mipmapped, repeating, anisotropic. */
export function imageTexture(gl: GL, img: TexImageSource, srgb: boolean, aniso: number): WebGLTexture {
  const t = gl.createTexture()!;
  gl.bindTexture(gl.TEXTURE_2D, t);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
  gl.texImage2D(gl.TEXTURE_2D, 0, srgb ? gl.SRGB8_ALPHA8 : gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, img);
  gl.generateMipmap(gl.TEXTURE_2D);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
  const ext = gl.getExtension("EXT_texture_filter_anisotropic");
  if (ext && aniso > 1) gl.texParameterf(gl.TEXTURE_2D, ext.TEXTURE_MAX_ANISOTROPY_EXT, Math.min(aniso, gl.getParameter(ext.MAX_TEXTURE_MAX_ANISOTROPY_EXT)));
  return t;
}

export function bytesTexture(gl: GL, size: number, data: Uint8Array, srgb: boolean, aniso: number): WebGLTexture {
  const t = gl.createTexture()!;
  gl.bindTexture(gl.TEXTURE_2D, t);
  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  gl.texImage2D(gl.TEXTURE_2D, 0, srgb ? gl.SRGB8_ALPHA8 : gl.RGBA8, size, size, 0, gl.RGBA, gl.UNSIGNED_BYTE, data);
  gl.generateMipmap(gl.TEXTURE_2D);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
  const ext = gl.getExtension("EXT_texture_filter_anisotropic");
  if (ext && aniso > 1) gl.texParameterf(gl.TEXTURE_2D, ext.TEXTURE_MAX_ANISOTROPY_EXT, Math.min(aniso, gl.getParameter(ext.MAX_TEXTURE_MAX_ANISOTROPY_EXT)));
  return t;
}
