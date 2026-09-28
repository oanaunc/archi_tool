# Oanarina Archi Tool for Windows — GPL-3.0-or-later
# Per-region mean colours of the Windows renders against the Mac renders (see render-match.mjs).
#   python3 windows/test/view3d/render-match.py <mac renders dir> <windows renders dir>
import sys, os, json
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from regions import REGIONS

mac_dir, win_dir = sys.argv[1], sys.argv[2]

def mean(im, b):
    w, h = im.size
    c = im.crop((int(b[0] * w), int(b[1] * h), max(int(b[0] * w) + 1, int(b[2] * w)), max(int(b[1] * h) + 1, int(b[3] * h))))
    px = list(c.getdata()); n = len(px)
    return [round(sum(p[i] for p in px) / n, 1) for i in range(3)]

def outline(im, regions):
    d = ImageDraw.Draw(im); w, h = im.size
    for k, b in regions.items():
        d.rectangle([b[0] * w, b[1] * h, b[2] * w, b[3] * h], outline=(255, 0, 255), width=1)
        d.text((b[0] * w + 2, b[1] * h + 1), k, fill=(255, 0, 255))

report = []
for f in sorted(os.listdir(win_dir)):
    if not f.startswith('cedar-house-') or not f.endswith('.png'): continue
    job = f[len('cedar-house-'):-4]
    regions = REGIONS[job.split('-')[0]]
    win = Image.open(os.path.join(win_dir, f)).convert('RGB')
    mp = os.path.join(mac_dir, f)
    entry = {'render': job, 'regions': {}}
    mac = Image.open(mp).convert('RGB').resize(win.size, Image.LANCZOS) if os.path.exists(mp) else None
    for k, b in regions.items():
        wm = mean(win, b)
        e = {'windows': wm}
        if mac is not None:
            mm = mean(mac, b)
            e['mac'] = mm
            e['diff'] = [round(a - c, 1) for a, c in zip(wm, mm)]
            e['absMean'] = round(sum(abs(x) for x in e['diff']) / 3, 1)
        entry['regions'][k] = e
    if mac is not None:
        entry['meanAbsDiff'] = round(sum(e['absMean'] for e in entry['regions'].values()) / len(regions), 1)
        c = Image.new('RGB', (win.width * 2 + 8, win.height + 22), (26, 27, 30))
        m2, w2 = mac.copy(), win.copy()
        outline(m2, regions); outline(w2, regions)
        c.paste(m2, (0, 22)); c.paste(w2, (win.width + 8, 22))
        d = ImageDraw.Draw(c)
        d.text((8, 5), 'Mac (SceneKit)  ' + job, fill=(230, 230, 230))
        d.text((win.width + 16, 5), 'Windows (WebGL 2)  mean |diff| %.1f' % entry['meanAbsDiff'], fill=(245, 197, 24))
        c.save(os.path.join(win_dir, 'compare-' + job + '.jpg'), quality=86)
    report.append(entry)
    line = '%-22s' % job
    for k, e in entry['regions'].items():
        line += ' %s %s' % (k, ('%+.0f' % (sum(e['diff']) / 3)) if 'diff' in e else '(%d,%d,%d)' % tuple(e['windows']))
    if 'meanAbsDiff' in entry: line += '  | mean |diff| %.1f' % entry['meanAbsDiff']
    print(line)
json.dump(report, open(os.path.join(win_dir, 'match.json'), 'w'), indent=1)
