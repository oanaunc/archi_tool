#!/usr/bin/env python3
# Oanarina Archi Tool — GPL-3.0-or-later
# Page-for-page comparison of two plotted PDFs (the Mac PLOT output and the archi-engine / Windows output of the same
# sheet): page count and sizes, then each page rendered at the same resolution and compared pixel by pixel. Writes
# <out>/page-<n>-mac.png, -win.png, -diff.png (differing pixels in red over a faded Mac page) and prints a summary.
#
#   python3 windows/tools/pdf_compare.py build/a102/A-102-mac.pdf build/a102/A-102-win.pdf build/a102/compare [dpi]
#
# The Mac reference comes from the Mac app itself: copy windows/tools/a102-reference.tut to build/tutorials/dev/30-a102.tut,
# write "check dev 30" to build/tutorials/.request and run ./scripts/q.sh tutorials (the recorder's dry run plays LAYOUT
# New "A-102 Plans", three MVIEWs, the title block and PLOT build/a102/A-102-mac.pdf in the Mac app); the Windows file from `./scripts/q.sh engine`
# (scripts/engine-smoke.jsonl ends with the same steps and plot.pdf). Rendering uses pypdfium2 (PDFium, the engine of the
# Edge / Chromium PDF viewer Windows users see) when installed, else poppler's pdftoppm.
import os, subprocess, sys, tempfile

def render(pdf, dpi, out_prefix):
    try:
        import pypdfium2 as pdfium
        doc = pdfium.PdfDocument(pdf)
        paths = []
        for i in range(len(doc)):
            p = f"{out_prefix}-{i + 1}.png"
            doc[i].render(scale=dpi / 72).to_pil().convert("RGB").save(p)
            paths.append(p)
        return paths, [tuple(round(v, 2) for v in doc[i].get_size()) for i in range(len(doc))], "pdfium"
    except ImportError:
        subprocess.run(["pdftoppm", "-r", str(dpi), "-png", pdf, out_prefix], check=True)
        d = os.path.dirname(out_prefix) or "."
        base = os.path.basename(out_prefix)
        paths = sorted(os.path.join(d, f) for f in os.listdir(d) if f.startswith(base + "-") and f.endswith(".png"))
        info = subprocess.run(["pdfinfo", pdf], capture_output=True, text=True).stdout
        size = next((l.split(":", 1)[1].split("pts")[0].strip() for l in info.splitlines() if l.startswith("Page size")), "?")
        return paths, [size] * len(paths), "poppler"

def main():
    if len(sys.argv) < 4:
        print(__doc__ or "usage: pdf_compare.py mac.pdf win.pdf outdir [dpi]"); return 2
    mac, win, out = sys.argv[1:4]
    dpi = int(sys.argv[4]) if len(sys.argv) > 4 else 150
    os.makedirs(out, exist_ok=True)
    from PIL import Image, ImageChops
    mp, ms, engine = render(mac, dpi, os.path.join(out, "page-mac"))
    wp, ws, _ = render(win, dpi, os.path.join(out, "page-win"))
    print(f"renderer {engine}, {dpi} dpi")
    print(f"pages: Mac {len(mp)}, Windows {len(wp)}" + ("" if len(mp) == len(wp) else "  <-- different page count"))
    worst = 0.0
    for i, (a, b) in enumerate(zip(mp, wp)):
        A, B = Image.open(a), Image.open(b)
        if A.size != B.size:
            print(f"page {i + 1}: size differs {ms[i]} vs {ws[i]}"); worst = 100; continue
        d = ImageChops.difference(A, B).convert("L")
        hist = d.histogram()
        n = A.size[0] * A.size[1]
        mean = sum(v * c for v, c in enumerate(hist)) / n
        over = sum(hist[26:])  # > 10 % of full scale
        pct = 100 * over / n
        worst = max(worst, pct)
        mask = d.point(lambda v: 255 if v > 25 else 0)
        faded = Image.blend(A, Image.new("RGB", A.size, "white"), 0.75)
        faded.paste(Image.new("RGB", A.size, (220, 0, 0)), mask=mask)
        faded.save(os.path.join(out, f"page-{i + 1}-diff.png"))
        # Where the differences are: a 6 x 4 grid of counts (row by row).
        W, H = A.size
        grid = []
        for gy in range(4):
            grid.append([sum(mask.crop((gx * W // 6, gy * H // 4, (gx + 1) * W // 6, (gy + 1) * H // 4)).histogram()[255:]) for gx in range(6)])
        print(f"page {i + 1}: size {ms[i]} / {ws[i]} pt, mean difference {mean:.2f}/255, pixels differing > 10 %: {over} ({pct:.3f} %)")
        print("  per region: " + " | ".join(" ".join(f"{c:5d}" for c in r) for r in grid))
    return 0 if len(mp) == len(wp) and worst < 1 else 1

if __name__ == "__main__":
    sys.exit(main())
