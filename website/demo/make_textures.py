#!/usr/bin/env python3
"""Procedural, seamless PBR textures for the demo projects (Oanarina Archi Tool — GPL-3.0-or-later).

Albedo 2048 px (JPEG, sRGB) plus tangent-space normal maps (<name>_n.jpg, OpenGL convention, derived from a height
field) and roughness maps (<name>_r.jpg) for: cedar boards, limestone ashlar, concrete paving with fine aggregate,
lawn with blade detail, tree foliage and hedge leaves. Every map tiles seamlessly.
Usage: make_textures.py <output folder> [size]"""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
S = int(sys.argv[2]) if len(sys.argv) > 2 else 2048
RNG = np.random.default_rng(20260926)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def vnoise(fx, fy, seed, size=S):
    """Periodic value noise with fx × fy cells over the tile (smooth interpolation, wraps at the edges)."""
    r = np.random.default_rng(seed).random((fy, fx))
    xs = np.arange(size) * fx / size
    ys = np.arange(size) * fy / size
    x0 = np.floor(xs).astype(int); y0 = np.floor(ys).astype(int)
    tx = xs - x0; ty = ys - y0
    tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty)
    x1 = (x0 + 1) % fx; y1 = (y0 + 1) % fy
    a = r[np.ix_(y0, x0)]; b = r[np.ix_(y0, x1)]; c = r[np.ix_(y1, x0)]; d = r[np.ix_(y1, x1)]
    top = a + (b - a) * tx[None, :]; bot = c + (d - c) * tx[None, :]
    return top + (bot - top) * ty[:, None]


def fbm(fx, fy, octaves, seed, size=S, gain=0.5):
    out = np.zeros((size, size)); amp = 1.0; norm = 0.0
    for o in range(octaves):
        out += amp * vnoise(fx * 2 ** o, fy * 2 ** o, seed + o * 101, size); norm += amp; amp *= gain
    return out / norm


def to_img(rgb):
    return Image.fromarray(np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8))


def save(name, rgb, height=None, rough=None, normal_strength=4.0, half_normal=False):
    to_img(rgb).save(os.path.join(OUT, name + ".jpg"), quality=88, optimize=True)
    if height is not None:
        # Central differences with wrap-around (seamless), strength in "texels per unit height".
        dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * normal_strength
        dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * normal_strength
        n = np.stack([-dx, dy, np.ones_like(height)], axis=-1)       # image rows go down: flip Y for OpenGL (+Y up)
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        nimg = to_img(n * 0.5 + 0.5)
        if half_normal:  # organic detail: half resolution keeps the files small
            nimg = nimg.resize((S // 2, S // 2), Image.LANCZOS)
        nimg.save(os.path.join(OUT, name + "_n.jpg"), quality=90, optimize=True)
    if rough is not None:
        r = Image.fromarray(np.clip(rough * 255 + 0.5, 0, 255).astype(np.uint8), "L").resize((S // 2, S // 2), Image.LANCZOS)
        r.save(os.path.join(OUT, name + "_r.jpg"), quality=90, optimize=True)
    print(name)


def cedar():
    """1200 mm tile: 12 horizontal boards of 100 mm with shadow gaps, butt joints, rich grain and a few knots."""
    boards = 12
    y = np.arange(S)[:, None] * np.ones((1, S))
    x = np.ones((S, 1)) * np.arange(S)[None, :]
    bh = S / boards
    bi = np.floor(y / bh).astype(int)
    v = (y - bi * bh) / bh                                          # 0..1 across the board
    rgb = np.zeros((S, S, 3)); height = np.zeros((S, S)); rough = np.zeros((S, S))
    palette = np.array([[0.55, 0.27, 0.15], [0.62, 0.33, 0.18], [0.48, 0.22, 0.12], [0.66, 0.38, 0.22],
                        [0.52, 0.25, 0.16], [0.58, 0.30, 0.14], [0.44, 0.21, 0.13], [0.63, 0.36, 0.24]])
    rng = np.random.default_rng(7)
    # Board segments: each board has one or two butt joints; each segment gets its own tone and grain phase.
    seg_tone = np.zeros((S, S, 3)); seg_phase = np.zeros((S, S)); joint = np.zeros((S, S))
    for b in range(boards):
        rows = slice(int(round(b * bh)), int(round((b + 1) * bh)))
        cuts = sorted(rng.uniform(0, S, rng.integers(1, 3)))
        edges = [0.0] + list(cuts) + [float(S)]
        for k in range(len(edges) - 1):
            cols = slice(int(edges[k]), int(edges[k + 1]))
            tone = palette[rng.integers(len(palette))] * rng.uniform(0.9, 1.1)
            seg_tone[rows, cols] = tone
            seg_phase[rows, cols] = rng.uniform(0, 100)
        for c in cuts:
            c = int(c); joint[rows, max(0, c - 2):c + 2] = 1
        # wrap: first and last segment share tone so the tile edge is not a seam
        first = int(edges[1]); last = int(edges[-2])
        seg_tone[rows, last:] = seg_tone[rows, 0:1]; seg_phase[rows, last:] = seg_phase[rows, 0:1]
    warp = fbm(6, 24, 4, 11) * 6 + fbm(3, 48, 3, 12) * 2.5
    rings = np.sin((v * 7 + seg_phase + warp) * math.pi * 2 + fbm(4, 64, 2, 13) * 3)
    fine = fbm(16, 256, 3, 14)                                       # long streaks along the board
    grain = 0.5 + 0.5 * rings
    shade = 0.82 + 0.22 * grain + 0.18 * (fine - 0.5) + 0.08 * (fbm(8, 12, 3, 15) - 0.5)
    rgb = seg_tone * shade[..., None]
    # darker latewood tint and slight silvering at the board lips
    rgb[..., 2] *= 0.92 + 0.1 * grain
    lip = smoothstep(0.0, 0.08, v) * (1 - smoothstep(0.86, 0.94, v))
    rgb *= (0.78 + 0.22 * lip)[..., None]
    # knots
    for _ in range(9):
        cx, cy = rng.uniform(0, S), rng.uniform(0, S); r = rng.uniform(5, 11) * S / 1024
        dxk = np.minimum(np.abs(x - cx), S - np.abs(x - cx)); dyk = np.minimum(np.abs(y - cy), S - np.abs(y - cy))
        d = np.sqrt((dxk / 1.6) ** 2 + dyk ** 2)
        k = np.exp(-(d / r) ** 2)
        rgb *= (1 - 0.55 * k)[..., None]
        height -= 0.5 * k
    # shadow gap between boards (bottom of each board) and butt joints
    gap = smoothstep(0.93, 0.975, v)
    rgb *= (1 - 0.85 * gap)[..., None]
    rgb *= (1 - 0.6 * joint)[..., None]
    height += 1.2 * lip - 2.5 * gap - 1.0 * joint + 0.35 * grain + 0.25 * fine
    rough = 0.62 + 0.18 * (1 - grain) * 0.8 + 0.1 * gap
    save("cedar", np.clip(rgb, 0, 1), height, rough, normal_strength=3.0)


def limestone():
    """1200 mm tile: 150 mm courses of 600 mm honed blocks, running bond, subtle veining, fossil flecks."""
    rows_n, bw = 8, S / 2
    y = np.arange(S)[:, None] * np.ones((1, S)); x = np.ones((S, 1)) * np.arange(S)[None, :]
    rh = S / rows_n
    r = np.floor(y / rh).astype(int)
    off = (r % 2) * bw / 2
    bx = np.floor((x - off) / bw).astype(int) % 2
    block = r * 2 + bx
    rng = np.random.default_rng(3)
    tones = rng.normal(0, 1, (rows_n * 2, 1)) * 0.022 + rng.normal(0, 1, (rows_n * 2, 3)) * 0.004 + np.array([0.86, 0.82, 0.73])
    rgb = tones[block]
    mott = fbm(6, 6, 6, 31)
    rgb *= (0.93 + 0.12 * mott)[..., None]
    # veins: thin lines along warped noise level sets
    vn = fbm(3, 5, 5, 32) + 0.35 * fbm(12, 12, 3, 33)
    vein = np.exp(-((np.abs(np.sin(vn * 9.0 * math.pi))) / 0.06) ** 2) * smoothstep(0.35, 0.65, fbm(4, 4, 3, 34))
    rgb *= (1 - 0.06 * vein)[..., None]
    rgb[..., 2] *= 1 - 0.04 * vein
    # flecks / fossil shells
    speck = RNG.random((S, S))
    fl = (speck > 0.9985).astype(float)
    fl = np.array(Image.fromarray((fl * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))) / 255.0
    rgb *= (1 - 0.18 * fl)[..., None]
    # joints (5 mm, slightly recessed, lighter mortar)
    jy = np.minimum(np.mod(y, rh), rh - np.mod(y, rh))
    jx = np.minimum(np.mod(x - off, bw), bw - np.mod(x - off, bw))
    j = 1 - smoothstep(1.5, 5.5, np.minimum(jx, jy) * 1024 / S)
    mortar = np.array([0.74, 0.71, 0.64])
    rgb = rgb * (1 - j[..., None]) + mortar * j[..., None] * (0.9 + 0.1 * mott[..., None])
    height = -1.5 * j + 0.08 * mott + 0.05 * fbm(64, 64, 2, 35) - 0.3 * fl
    rough = 0.82 + 0.08 * j - 0.05 * mott
    save("limestone", np.clip(rgb, 0, 1), height, rough, normal_strength=3.0)


def concrete():
    """3000 mm tile of broom-finished paving with fine aggregate and saw-cut joints on two edges."""
    base = np.array([0.74, 0.72, 0.68])
    mott = fbm(5, 5, 6, 41)
    cloud = fbm(20, 20, 4, 42)
    rgb = base * (0.9 + 0.14 * mott[..., None] + 0.05 * cloud[..., None])
    # fine aggregate: small dots of varied tone (2–5 mm)
    agg = np.zeros((S, S))
    img = Image.new("L", (S, S), 128); d = ImageDraw.Draw(img)
    rng = np.random.default_rng(43)
    for _ in range(int(60000 * (S / 2048) ** 2)):
        cx, cy = rng.uniform(0, S), rng.uniform(0, S); rad = rng.uniform(0.5, 2.2) * S / 2048
        t = int(rng.choice([rng.integers(40, 100), rng.integers(160, 230)]))
        for ox in (0, -S, S):
            for oy in (0, -S, S):
                if 0 <= cx + ox + rad and cx + ox - rad <= S and 0 <= cy + oy + rad and cy + oy - rad <= S:
                    d.ellipse([cx + ox - rad, cy + oy - rad, cx + ox + rad, cy + oy + rad], fill=t)
    agg = (np.array(img) / 255.0 - 0.5)
    rgb *= (1 + 0.28 * agg)[..., None]
    # broom texture: fine streaks across the tile
    broom = fbm(512, 6, 2, 44) - 0.5
    rgb *= (1 + 0.05 * broom)[..., None]
    # saw-cut joints along the tile edges (appear every 3 m)
    y = np.arange(S)[:, None] * np.ones((1, S)); x = np.ones((S, 1)) * np.arange(S)[None, :]
    e = np.minimum(np.minimum(x, S - x), np.minimum(y, S - y)) * 3000 / S
    j = 1 - smoothstep(2, 6, e)
    rgb *= (1 - 0.45 * j)[..., None]
    height = 0.6 * agg + 0.25 * broom + 0.1 * mott - 2.0 * j
    rough = 0.86 - 0.08 * mott + 0.05 * agg
    save("concrete", np.clip(rgb, 0, 1), height, rough, normal_strength=2.0, half_normal=True)


def blades(bg, cols, count, length, width, seed, size=S, clump=None):
    """Draws short grass-blade strokes (wrapped at the edges for a seamless tile)."""
    img = Image.fromarray(np.clip(bg * 255, 0, 255).astype(np.uint8)); d = ImageDraw.Draw(img)
    hmap = Image.new("L", (size, size), 0); dh = ImageDraw.Draw(hmap)
    rng = np.random.default_rng(seed)
    for _ in range(count):
        x0, y0 = rng.uniform(0, size), rng.uniform(0, size)
        a = rng.uniform(0, 2 * math.pi); ln = rng.uniform(*length)
        c = cols[rng.integers(len(cols))] * rng.uniform(0.8, 1.15)
        if clump is not None:
            c = c * (0.8 + 0.35 * clump[int(y0) % size, int(x0) % size])
        col = tuple(int(max(0, min(255, v * 255))) for v in c)
        x1, y1 = x0 + math.cos(a) * ln, y0 + math.sin(a) * ln
        wdt = max(1, int(round(rng.uniform(*width))))
        hv = int(rng.uniform(120, 255))
        for ox in (0, -size, size):
            for oy in (0, -size, size):
                if -ln <= x0 + ox <= size + ln and -ln <= y0 + oy <= size + ln:
                    d.line([(x0 + ox, y0 + oy), (x1 + ox, y1 + oy)], fill=col, width=wdt)
                    dh.line([(x0 + ox, y0 + oy), (x1 + ox, y1 + oy)], fill=hv, width=wdt)
    return np.array(img) / 255.0, np.array(hmap) / 255.0


def lawn():
    """2500 mm tile of mown lawn: layered blade strokes over soil-dark depth, with clumps and dry patches."""
    clump = fbm(8, 8, 4, 51)
    dry = smoothstep(0.66, 0.9, fbm(3, 3, 4, 52)) * 0.6
    bg = np.array([0.11, 0.17, 0.06]) * (0.8 + 0.4 * clump[..., None])
    cols = np.array([[0.24, 0.38, 0.11], [0.30, 0.45, 0.14], [0.20, 0.33, 0.09], [0.36, 0.50, 0.17], [0.42, 0.52, 0.22], [0.27, 0.40, 0.10]])
    n = int(260000 * (S / 2048) ** 2)
    rgb, h = blades(bg, cols, n, (10 * S / 2048, 26 * S / 2048), (1.2, 2.6), 53, clump=clump)
    straw = np.array([0.55, 0.52, 0.30])
    rgb = rgb * (1 - 0.35 * dry[..., None]) + straw * 0.35 * dry[..., None] * (0.7 + 0.5 * rgb.mean(axis=-1, keepdims=True) / 0.35)
    rgb = np.array(to_img(rgb).filter(ImageFilter.GaussianBlur(0.35))) / 255.0
    rough = 0.9 - 0.1 * h
    save("lawn", np.clip(rgb, 0, 1), h * 1.5 + 0.3 * clump, rough, normal_strength=2.5, half_normal=True)


def leaf_layer(size, n, rad, cols, seed, shadow=0.35):
    """Overlapping leaf ellipses (rotated) with a darker core between them: foliage seen from outside a crown."""
    img = Image.new("RGB", (size, size), (int(cols[0][0] * 60), int(cols[0][1] * 70), int(cols[0][2] * 50)))
    hmap = Image.new("L", (size, size), 0)
    rng = np.random.default_rng(seed)
    for _ in range(n):
        cx, cy = rng.uniform(0, size), rng.uniform(0, size)
        r = rng.uniform(*rad); ang = rng.uniform(0, 180)
        c = cols[rng.integers(len(cols))] * rng.uniform(0.75, 1.2)
        # leaf sprite: ellipse 2.2:1 with a lighter upper half (sky light) and a midrib
        w, hgt = int(r * 2.3) + 2, int(r) + 2
        spr = Image.new("RGBA", (w * 2 + 4, w * 2 + 4), (0, 0, 0, 0)); ds = ImageDraw.Draw(spr)
        cxs = cys = w + 2
        ds.ellipse([cxs - w, cys - hgt, cxs + w, cys + hgt], fill=tuple(int(max(0, min(255, v * 255))) for v in c) + (255,))
        ds.ellipse([cxs - w + 2, cys - hgt + 1, cxs + w - 2, cys], fill=tuple(int(max(0, min(255, v * 275))) for v in c) + (255,))
        ds.line([(cxs - w + 2, cys), (cxs + w - 2, cys)], fill=tuple(int(max(0, min(255, v * 200))) for v in c) + (255,), width=1)
        spr = spr.rotate(ang, resample=Image.BICUBIC)
        hs = Image.new("L", spr.size, 0); hs.paste(int(rng.uniform(140, 255)), mask=spr.split()[3])
        for ox in (0, -size, size):
            for oy in (0, -size, size):
                px, py = int(cx + ox - spr.size[0] / 2), int(cy + oy - spr.size[1] / 2)
                if -spr.size[0] < px < size and -spr.size[1] < py < size:
                    img.paste(spr, (px, py), spr)
                    hmap.paste(hs, (px, py), spr.split()[3])
    return np.array(img) / 255.0, np.array(hmap) / 255.0


def leaves():
    """900 mm tile of birch/maple-like foliage: bright young leaves over dark gaps."""
    cols = np.array([[0.36, 0.50, 0.14], [0.44, 0.58, 0.18], [0.30, 0.44, 0.12], [0.50, 0.62, 0.24], [0.26, 0.38, 0.10]])
    rgb, h = leaf_layer(S, int(16000 * (S / 2048) ** 2), (10 * S / 2048, 22 * S / 2048), cols, 61)
    light = fbm(4, 4, 4, 62)
    rgb *= (0.75 + 0.45 * light[..., None])
    save("leaves", np.clip(rgb, 0, 1), h * 1.4 + 0.5 * light, 0.75 - 0.15 * h, normal_strength=3.0, half_normal=True)


def hedge():
    """800 mm tile of clipped hedge (box/privet): small dark glossy leaves densely packed."""
    cols = np.array([[0.14, 0.26, 0.10], [0.18, 0.31, 0.12], [0.11, 0.22, 0.08], [0.22, 0.36, 0.15]])
    rgb, h = leaf_layer(S, int(38000 * (S / 2048) ** 2), (5 * S / 2048, 10 * S / 2048), cols, 71)
    light = fbm(6, 6, 4, 72)
    rgb *= (0.7 + 0.5 * light[..., None])
    save("hedge", np.clip(rgb, 0, 1), h * 1.2 + 0.6 * light, 0.7 - 0.15 * h, normal_strength=3.0, half_normal=True)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[3:])
    for name, fn in [("cedar", cedar), ("limestone", limestone), ("concrete", concrete), ("lawn", lawn), ("leaves", leaves), ("hedge", hedge)]:
        if not only or name in only:
            fn()
