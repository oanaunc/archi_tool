# Oanarina Archi Tool for Windows — GPL-3.0-or-later
# Round-4 render match report: Mac | Windows before | Windows after for each Cedar House render, with the per-region
# mean colours (regions.py) and the mean |diff| in 8-bit levels, written to windows/test-results/render-match-r4/.
#   python3 windows/test/view3d/render-match-r4.py <mac renders> <before dir> <after dir> <out dir>
import sys, os, json
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from regions import REGIONS

mac_dir, before_dir, after_dir, out_dir = sys.argv[1:5]
os.makedirs(out_dir, exist_ok=True)

def mean(im, b):
    w, h = im.size
    c = im.crop((int(b[0] * w), int(b[1] * h), max(int(b[0] * w) + 1, int(b[2] * w)), max(int(b[1] * h) + 1, int(b[3] * h))))
    px = c.resize((max(1, c.width // 2), max(1, c.height // 2)), Image.BOX).getdata() if c.width > 4 and c.height > 4 else c.getdata()
    px = list(px); n = len(px)
    return [round(sum(p[i] for p in px) / n, 1) for i in range(3)]

report = []
for f in sorted(os.listdir(after_dir)):
    if not (f.startswith('cedar-house-') and f.endswith('.png')): continue
    mp = os.path.join(mac_dir, f)
    if not os.path.exists(mp): continue
    job = f[len('cedar-house-'):-4]
    regions = REGIONS[job.split('-')[0]]
    after = Image.open(os.path.join(after_dir, f)).convert('RGB')
    bp = os.path.join(before_dir, f)
    before = Image.open(bp).convert('RGB').resize(after.size) if os.path.exists(bp) else None
    mac = Image.open(mp).convert('RGB').resize(after.size, Image.LANCZOS)
    e = {'render': job, 'regions': {}}
    for k, b in regions.items():
        m, a = mean(mac, b), mean(after, b)
        r = {'mac': m, 'after': a, 'afterDiff': round(sum(x - y for x, y in zip(a, m)) / 3, 1)}
        if before is not None:
            bb = mean(before, b); r['before'] = bb; r['beforeDiff'] = round(sum(x - y for x, y in zip(bb, m)) / 3, 1)
        e['regions'][k] = r
    def mad(key):
        vals = [sum(abs(x - y) for x, y in zip(r[key], r['mac'])) / 3 for r in e['regions'].values() if key in r]
        return round(sum(vals) / len(vals), 1) if vals else None
    e['before'] = mad('before'); e['after'] = mad('after')
    report.append(e)
    W, H = after.size
    panels = [('Mac (SceneKit)', mac), ('Windows before  |diff| %s' % e['before'], before), ('Windows after  |diff| %s' % e['after'], after)]
    panels = [p for p in panels if p[1] is not None]
    c = Image.new('RGB', (W * len(panels) + 8 * (len(panels) - 1), H + 22), (26, 27, 30))
    d = ImageDraw.Draw(c)
    for i, (t, im) in enumerate(panels):
        x = i * (W + 8)
        c.paste(im, (x, 22))
        d.text((x + 8, 5), t + ('  ' + job if i == 0 else ''), fill=(245, 197, 24) if i == len(panels) - 1 else (230, 230, 230))
    c.save(os.path.join(out_dir, 'compare-' + job + '.jpg'), quality=85)
    line = '%-20s before %4s  after %4s  |' % (job, e['before'], e['after'])
    for k, r in e['regions'].items(): line += ' %s %+.0f→%+.0f' % (k, r.get('beforeDiff', 0), r['afterDiff'])
    print(line)
json.dump(report, open(os.path.join(out_dir, 'before-after.json'), 'w'), indent=1)
