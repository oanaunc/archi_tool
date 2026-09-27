// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// Minimal MP4 (ISO BMFF) writer for one video track: H.264 (avc1 + avcC, from WebCodecs "avc" format chunks) or VP9
// (vp09 + vpcC). All samples in one chunk after the movie box; constant frame rate; sync-sample table from key frames.
// The Mac writes H.264 MP4 with AVAssetWriter (RenderEngine.writeVideo); this produces the same kind of file.

export interface Mp4Sample { data: Uint8Array; key: boolean }
export interface Mp4Track { codec: "avc1" | "vp09"; width: number; height: number; fps: number; description?: Uint8Array; samples: Mp4Sample[] }

class W {
  parts: Uint8Array[] = [];
  size = 0;
  u8(v: number) { this.push(new Uint8Array([v & 255])); }
  u16(v: number) { this.push(new Uint8Array([(v >> 8) & 255, v & 255])); }
  u24(v: number) { this.push(new Uint8Array([(v >> 16) & 255, (v >> 8) & 255, v & 255])); }
  u32(v: number) { this.push(new Uint8Array([(v >>> 24) & 255, (v >>> 16) & 255, (v >>> 8) & 255, v & 255])); }
  str(s: string) { this.push(new Uint8Array([...s].map((c) => c.charCodeAt(0) & 255))); }
  zeros(n: number) { this.push(new Uint8Array(n)); }
  push(b: Uint8Array) { this.parts.push(b); this.size += b.length; }
  bytes(): Uint8Array { const out = new Uint8Array(this.size); let o = 0; for (const p of this.parts) { out.set(p, o); o += p.length; } return out; }
}

function box(type: string, ...content: Uint8Array[]): Uint8Array {
  const w = new W();
  const size = 8 + content.reduce((s, c) => s + c.length, 0);
  w.u32(size); w.str(type);
  for (const c of content) w.push(c);
  return w.bytes();
}
function full(type: string, version: number, flags: number, ...content: Uint8Array[]): Uint8Array {
  const w = new W(); w.u8(version); w.u24(flags);
  return box(type, w.bytes(), ...content);
}
function bytes(f: (w: W) => void): Uint8Array { const w = new W(); f(w); return w.bytes(); }
const MATRIX = [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000];

export function mp4(t: Mp4Track): Uint8Array {
  const n = t.samples.length;
  const timescale = t.fps * 1000, delta = 1000;
  const duration = n * delta;
  const durationMs = Math.round((n / t.fps) * 1000);
  const ftyp = box("ftyp", bytes((w) => { w.str("isom"); w.u32(512); w.str("isom"); w.str("iso2"); w.str(t.codec === "avc1" ? "avc1" : "vp09"); w.str("mp41"); }));
  const mvhd = full("mvhd", 0, 0, bytes((w) => {
    w.u32(0); w.u32(0); w.u32(1000); w.u32(durationMs); w.u32(0x00010000); w.u16(0x0100); w.zeros(10);
    for (const m of MATRIX) w.u32(m);
    w.zeros(24); w.u32(2);
  }));
  const tkhd = full("tkhd", 0, 3, bytes((w) => {
    w.u32(0); w.u32(0); w.u32(1); w.u32(0); w.u32(durationMs); w.zeros(8); w.u16(0); w.u16(0); w.u16(0); w.u16(0);
    for (const m of MATRIX) w.u32(m);
    w.u32(t.width << 16); w.u32(t.height << 16);
  }));
  const mdhd = full("mdhd", 0, 0, bytes((w) => { w.u32(0); w.u32(0); w.u32(timescale); w.u32(duration); w.u16(0x55c4); w.u16(0); }));
  const hdlr = full("hdlr", 0, 0, bytes((w) => { w.u32(0); w.str("vide"); w.zeros(12); w.str("VideoHandler"); w.u8(0); }));
  const vmhd = full("vmhd", 0, 1, bytes((w) => { w.u16(0); w.zeros(6); }));
  const dinf = box("dinf", full("dref", 0, 0, bytes((w) => w.u32(1)), full("url ", 0, 1)));
  const codecBox = t.codec === "avc1"
    ? box("avcC", t.description ?? new Uint8Array())
    : full("vpcC", 1, 0, bytes((w) => { w.u8(0); w.u8(31); w.u8((8 << 4) | (1 << 1) | 0); w.u8(1); w.u8(1); w.u8(1); w.u16(0); }));
  const entry = box(t.codec, bytes((w) => {
    w.zeros(6); w.u16(1); w.zeros(16); w.u16(t.width); w.u16(t.height); w.u32(0x00480000); w.u32(0x00480000); w.u32(0); w.u16(1);
    const name = "Oanarina Archi Tool";
    w.u8(name.length); w.str(name); w.zeros(31 - name.length); w.u16(0x0018); w.u16(0xffff);
  }), codecBox);
  const stsd = full("stsd", 0, 0, bytes((w) => w.u32(1)), entry);
  const stts = full("stts", 0, 0, bytes((w) => { w.u32(1); w.u32(n); w.u32(delta); }));
  const keys = t.samples.map((s, i) => (s.key ? i + 1 : 0)).filter((k) => k > 0);
  const stss = full("stss", 0, 0, bytes((w) => { w.u32(keys.length); for (const k of keys) w.u32(k); }));
  const stsc = full("stsc", 0, 0, bytes((w) => { w.u32(1); w.u32(1); w.u32(n); w.u32(1); }));
  const stsz = full("stsz", 0, 0, bytes((w) => { w.u32(0); w.u32(n); for (const s of t.samples) w.u32(s.data.length); }));
  // The chunk offset is known once the movie box size is: build with a placeholder, then patch.
  const build = (offset: number) => {
    const stco = full("stco", 0, 0, bytes((w) => { w.u32(1); w.u32(offset); }));
    const stbl = box("stbl", stsd, stts, stss, stsc, stsz, stco);
    const minf = box("minf", vmhd, dinf, stbl);
    const mdia = box("mdia", mdhd, hdlr, minf);
    const trak = box("trak", tkhd, mdia);
    return box("moov", mvhd, trak);
  };
  const moov0 = build(0);
  const dataStart = ftyp.length + moov0.length + 8;
  const moov = build(dataStart);
  const mdatSize = 8 + t.samples.reduce((s, x) => s + x.data.length, 0);
  const out = new Uint8Array(ftyp.length + moov.length + mdatSize);
  out.set(ftyp, 0);
  out.set(moov, ftyp.length);
  let o = ftyp.length + moov.length;
  out.set(bytes((w) => { w.u32(mdatSize); w.str("mdat"); }), o);
  o += 8;
  for (const s of t.samples) { out.set(s.data, o); o += s.data.length; }
  return out;
}

/** Top-level boxes of an MP4 file (tests): [type, size]. */
export function boxes(b: Uint8Array): [string, number][] {
  const out: [string, number][] = [];
  let o = 0;
  while (o + 8 <= b.length) {
    const size = ((b[o] << 24) >>> 0) + (b[o + 1] << 16) + (b[o + 2] << 8) + b[o + 3];
    out.push([String.fromCharCode(b[o + 4], b[o + 5], b[o + 6], b[o + 7]), size]);
    if (size < 8) break;
    o += size;
  }
  return out;
}
