#!/usr/bin/env python3
"""Procedural, seamless textures for the demo projects (cedar boards, limestone, concrete, lawn, foliage)."""
import random, sys, os
from PIL import Image, ImageDraw, ImageFilter
OUT = sys.argv[1]; S = 1024
def noise(img, amt, seed, blur=0.6):
    rnd = random.Random(seed); px = img.load()
    for y in range(S):
        for x in range(S):
            r, g, b = px[x, y]; d = rnd.randint(-amt, amt)
            px[x, y] = (max(0, min(255, r + d)), max(0, min(255, g + d)), max(0, min(255, b + d)))
    return img.filter(ImageFilter.GaussianBlur(blur))
def cedar():  # 1200 mm tile, 12 boards of 100 mm
    rnd = random.Random(7); img = Image.new('RGB', (S, S)); d = ImageDraw.Draw(img); bh = S // 12
    for i in range(12):
        base = (rnd.randint(122, 150), rnd.randint(56, 72), rnd.randint(34, 46))
        d.rectangle([0, i * bh, S, (i + 1) * bh], fill=base)
        for k in range(60):  # horizontal grain streaks
            y = i * bh + rnd.randint(2, bh - 3); x0 = rnd.randint(-200, S); ln = rnd.randint(120, 600); t = rnd.randint(-22, 16)
            c = tuple(max(0, min(255, v + t)) for v in base)
            d.line([(x0, y), (x0 + ln, y + rnd.randint(-1, 1))], fill=c, width=rnd.randint(1, 2))
            if x0 + ln > S: d.line([(x0 - S, y), (x0 + ln - S, y)], fill=c, width=1)
        d.rectangle([0, (i + 1) * bh - 3, S, (i + 1) * bh], fill=(40, 20, 12))  # shadow gap
    return noise(img, 6, 1)
def limestone():  # 1200 mm tile, blocks 600 x 150
    rnd = random.Random(3); img = Image.new('RGB', (S, S), (222, 214, 196)); d = ImageDraw.Draw(img); rh = S // 8; bw = S // 2
    for r in range(8):
        off = (r % 2) * bw // 2
        for c in range(-1, 3):
            x0 = c * bw + off; t = rnd.randint(-10, 10)
            d.rectangle([x0 + 2, r * rh + 2, x0 + bw - 2, (r + 1) * rh - 2], fill=(224 + t, 216 + t, 198 + t))
        d.line([(0, r * rh), (S, r * rh)], fill=(186, 178, 160), width=3)
        for c in range(-1, 3): d.line([(c * bw + off, r * rh), (c * bw + off, (r + 1) * rh)], fill=(186, 178, 160), width=3)
    return noise(img, 10, 2, 0.8)
def concrete():  # 3000 mm tile with joints
    img = Image.new('RGB', (S, S), (206, 200, 190)); img = noise(img, 12, 4, 1.2); d = ImageDraw.Draw(img)
    d.line([(0, 0), (S, 0)], fill=(160, 154, 146), width=4); d.line([(0, 0), (0, S)], fill=(160, 154, 146), width=4)
    return img
def lawn():
    img = Image.new('RGB', (S, S), (78, 118, 52)); return noise(img, 26, 5, 1.0)
def leaves():
    rnd = random.Random(9); img = Image.new('RGB', (S, S), (96, 124, 40)); d = ImageDraw.Draw(img)
    for _ in range(5000):
        x, y, r = rnd.randint(0, S), rnd.randint(0, S), rnd.randint(4, 12); t = rnd.randint(-40, 40)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(max(0, 100 + t), max(0, 132 + t), max(0, 40 + t // 2)))
    return img.filter(ImageFilter.GaussianBlur(0.7))
def hedge():
    rnd = random.Random(11); img = Image.new('RGB', (S, S), (30, 56, 26)); d = ImageDraw.Draw(img)
    for _ in range(7000):
        x, y, r = rnd.randint(0, S), rnd.randint(0, S), rnd.randint(3, 8); t = rnd.randint(-18, 22)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(max(0, 34 + t), max(0, 64 + t), max(0, 28 + t // 2)))
    return img
for name, fn in [("cedar", cedar), ("limestone", limestone), ("concrete", concrete), ("lawn", lawn), ("leaves", leaves), ("hedge", hedge)]:
    fn().save(os.path.join(OUT, name + ".jpg"), quality=88); print(name)
