#!/usr/bin/env python3
"""Side-by-side comparison of Mac screenshots (left) with the Windows shell screenshots (right).
Usage: python3 test/tools/compare.py <mac-refs dir> test-results"""
import sys, os
from PIL import Image, ImageDraw
refs, res = sys.argv[1], sys.argv[2]
pairs = [("tut01-architecture.jpg", "cedar-plan-architecture.png", "compare-plan-architecture.jpg"),
         ("tut01a-start.jpg", "start-screen.png", "compare-start.jpg"),
         ("workspace-home.jpg", "cedar-plan-home.png", "compare-home-ribbon.jpg")]
for mac, win, out in pairs:
    a, b = os.path.join(refs, mac), os.path.join(res, win)
    if not (os.path.exists(a) and os.path.exists(b)): continue
    A, B = Image.open(a).convert("RGB").resize((1440, 900)), Image.open(b).convert("RGB").resize((1440, 900))
    C = Image.new("RGB", (2900, 940), (12, 12, 14)); C.paste(A, (0, 40)); C.paste(B, (1460, 40))
    d = ImageDraw.Draw(C); d.text((10, 12), "Mac (reference)", fill=(245, 197, 24)); d.text((1470, 12), "Windows shell (fixture engine)", fill=(245, 197, 24))
    C.save(os.path.join(res, out), quality=88); print("wrote", out)
