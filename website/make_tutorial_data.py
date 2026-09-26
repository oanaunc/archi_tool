#!/usr/bin/env python3
"""Tutorial chapters for the website: match each .tut script's captions to the recorder log timestamps,
transcode the recordings for the web and write posters. Usage: make_tutorial_data.py <website-root> [--no-video]"""
import json, re, shlex, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]; SITE = Path(sys.argv[1]); NOVID = '--no-video' in sys.argv
TUT, REC = ROOT / 'tutorials', ROOT / 'build' / 'tutorials'
VID, POS = SITE / 'videos' / 'archi-tool', SITE / 'images' / 'apps' / 'archi-tool' / 'tutorials'
VID.mkdir(parents=True, exist_ok=True); POS.mkdir(parents=True, exist_ok=True)

def dur(p): return float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',str(p)]).decode())
out = []
for tut in sorted(TUT.glob('[01][0-9]-*.tut')):
    slug = tut.stem; mp4 = REC / f'{slug}.mp4'; log = REC / f'{slug}.log'
    if not mp4.exists(): continue
    head, _, body = tut.read_text().partition('\n---\n')
    meta = dict(re.findall(r'^(title|summary):\s*(.+)$', head, re.M))
    logs = []
    for ln in log.read_text(errors='ignore').splitlines() if log.exists() else []:
        m = re.match(r'^\[\s*([0-9.]+)\] » ?(.*)$', ln)
        if m: logs.append((float(m.group(1)), m.group(2).strip()))
    ptr, anchor, waits, steps = 0, 0.0, 0.0, []
    def find(pred):
        global ptr
        for j in range(ptr, min(ptr + 60, len(logs))):
            if pred(logs[j][1]): ptr = j + 1; return logs[j][0]
        return None
    for raw in body.splitlines():
        s = raw.strip()
        if not s or s.startswith('#'): continue
        try: tok = shlex.split(s)
        except ValueError: tok = s.split()
        k = tok[0]
        if k == 'wait' and len(tok) > 1:
            try: waits += float(tok[1])
            except ValueError: pass
            continue
        if k == 'caption' and len(tok) >= 2:
            t = 0.0 if not steps and anchor == 0 else anchor + waits + 0.3
            if steps: t = max(t, steps[-1][0] + 1.0)
            steps.append([round(t, 1), tok[1], tok[2] if len(tok) > 2 else ''])
            continue
        t = None
        if k == 'click': t = find(lambda e: e.startswith('click'))
        elif k == 'pick': t = find(lambda e: e.startswith('pick'))
        elif k == 'enter': t = find(lambda e: e == '')
        elif k == 'type' and len(tok) > 1:
            t = find(lambda e, w=tok[1]: e == w)
            if t is not None:   # one log entry per typed word: follow the chain to the last one
                for w in tok[2:]:
                    if ptr < len(logs) and (logs[ptr][1] == w or (w == ';' and logs[ptr][1] == '')): t = logs[ptr][0]; ptr += 1
                    else: break
        if t is not None:
            # a caption placed just before this action cannot be later than the action itself
            if steps and steps[-1][0] > t - 0.8 and len(steps) > 1: steps[-1][0] = round(max(steps[-2][0] + 1.0, t - 2.5), 1)
            anchor, waits = t, 0.0
    d = dur(mp4)
    steps = [[st[0] + (1.0 if st[0] else 0), st[1], st[2]] for st in steps]
    steps = [st for st in steps if st[0] < d - 1]
    if not NOVID:
        subprocess.run(['ffmpeg','-loglevel','error','-y','-i',str(mp4),'-vf','scale=1600:-2:flags=lanczos,format=yuv420p',
                        '-c:v','libx264','-preset','medium','-crf','24','-tune','animation','-movflags','+faststart','-an',str(VID / f'{slug}.mp4')], check=True)
    if True:
        pt = steps[-1][0] + 2 if steps else d * .6
        subprocess.run(['ffmpeg','-loglevel','error','-y','-ss',f'{min(pt, d - 1):.1f}','-i',str(mp4),'-frames:v','1','-vf','scale=1280:-2:flags=lanczos',
                        '-q:v','4',str(POS / f'{slug}.jpg')], check=True)
    n = int(slug[:2]); m_, s_ = divmod(int(round(d)), 60)
    out.append({'n': n, 'slug': slug, 'title': meta.get('title', slug), 'summary': meta.get('summary', ''), 'dur': f'{m_}:{s_:02d}', 'steps': steps})
    print(slug, f'{d:.0f}s', len(steps), 'chapters', [st[0] for st in steps])
(ROOT / 'website' / 'tutorials.json').write_text(json.dumps(out, ensure_ascii=False, indent=1))
