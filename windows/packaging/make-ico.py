#!/usr/bin/env python3
# Oanarina Archi Tool — GPL-3.0-or-later
# Converts the Mac app icon into a Windows .ico (16…256 px, PNG-compressed entries) for electron-builder.
# Sources, first found wins: app/Resources/AppIcon.icns, build/AppIcon.iconset/*.png, app/Resources/AppIcon/*.png.
# Usage: python make-ico.py <repo root> <out.ico>        (needs Pillow: pip install pillow)
import glob, os, sys

try:
    from PIL import Image
except ImportError:
    sys.exit("make-ico: Pillow is missing (pip install pillow)")

root, out = (sys.argv[1:3] + [None, None])[:2]
if not root or not out:
    sys.exit("usage: make-ico.py <repo root> <out.ico>")
SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]

def largest_png(folder):
    files = glob.glob(os.path.join(folder, "*.png"))
    if not files:
        return None
    return max((Image.open(f) for f in files), key=lambda im: im.size[0] * im.size[1])

img = None
icns = os.path.join(root, "app", "Resources", "AppIcon.icns")
if os.path.isfile(icns):
    im = Image.open(icns)
    best = max(im.info.get("sizes", {im.size}), key=lambda s: s[0] * s[1] * (s[2] if len(s) > 2 else 1))
    im.size = best if len(best) == 3 else im.size  # Pillow's ICNS plugin picks a size by assigning .size
    try:
        im.load()
    except Exception:
        im = Image.open(icns); im.load()
    img = im
for folder in ("build/AppIcon.iconset", "app/Resources/AppIcon", "app/Resources/AppIcon.iconset"):
    if img is None:
        img = largest_png(os.path.join(root, folder))
if img is None:
    sys.exit("make-ico: no app icon found (app/Resources/AppIcon.icns or an AppIcon iconset with PNGs)")
img = img.convert("RGBA")
if img.size[0] < 256:
    print(f"make-ico: warning, largest source image is only {img.size[0]} px", file=sys.stderr)
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
img.resize((256, 256), Image.LANCZOS).save(out, format="ICO", sizes=[(s, s) for s in SIZES])
check = Image.open(out)
print(f"make-ico: {out} from {img.size[0]} px source, sizes {sorted(check.info.get('sizes', []))}")
