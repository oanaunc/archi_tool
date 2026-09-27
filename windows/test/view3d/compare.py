# Oanarina Archi Tool for Windows — GPL-3.0-or-later
# Side-by-side (Mac | Windows) comparison images and simple statistics for the 3D renders.
#   python3 windows/test/view3d/compare.py <mac renders dir (build/renders)> <windows renders dir (windows/test-results/3d)>
import sys, os, json, warnings
warnings.filterwarnings('ignore')
from PIL import Image, ImageDraw, ImageStat
mac, win = sys.argv[1], sys.argv[2]
out = []
for f in sorted(os.listdir(win)):
    if not f.endswith('.png') or f.startswith('compare-'): continue
    mp = os.path.join(mac, f)
    w = Image.open(os.path.join(win, f)).convert('RGB')
    if not os.path.exists(mp):
        continue
    m = Image.open(mp).convert('RGB').resize(w.size, Image.LANCZOS)
    c = Image.new('RGB', (w.width * 2 + 8, w.height + 24), (26, 27, 30))
    c.paste(m, (0, 24)); c.paste(w, (w.width + 8, 24))
    d = ImageDraw.Draw(c)
    d.text((8, 6), 'Mac (SceneKit)  ' + f, fill=(230, 230, 230)); d.text((w.width + 16, 6), 'Windows (WebGL 2)', fill=(245, 197, 24))
    c.save(os.path.join(win, 'compare-' + f.replace('.png', '.jpg')), quality=88)
    sm, sw = ImageStat.Stat(m), ImageStat.Stat(w)
    # Mean absolute difference on 1/8-size thumbnails (structure + tone), 0 = identical.
    tm, tw = m.resize((w.width // 8, w.height // 8)), w.resize((w.width // 8, w.height // 8))
    diff = sum(abs(a - b) for pa, pb in zip(tm.getdata(), tw.getdata()) for a, b in zip(pa, pb)) / (tm.width * tm.height * 3)
    out.append({'image': f, 'macMean': [round(v, 1) for v in sm.mean], 'winMean': [round(v, 1) for v in sw.mean], 'meanAbsDiff': round(diff, 1)})
    print(f, 'mac', [round(v) for v in sm.mean], 'win', [round(v) for v in sw.mean], 'diff', round(diff, 1))
json.dump(out, open(os.path.join(win, 'compare.json'), 'w'), indent=1)
